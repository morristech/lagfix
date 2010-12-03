#!/bin/bash
#
# By François SIMOND for project-voodoo.org
# License GPL v3
#
# generate 4 Voodoo ramdisks
# use a standard ramdisk directory as input, and make it Voodoo!
# recommanded to wipe the destination directory first
#
# see README for usage

echo -e "\nVoodoo ramdisk injector:\n"

display_option()
{
	echo "Voodoo injector option: $1"
}


# parse options
while getopts "s:d:p:t:x: :uw" opt
do
	case "$opt" in
		s) source=`readlink -f "$OPTARG"`;;
		d) dest=`readlink -f "$OPTARG"`;;
		p) voodoo_ramdisk_parts=`readlink -f "$OPTARG"`;;
		t) stages_source=`readlink -f "$OPTARG"`;;
		x) extentions_source=`readlink -f "$OPTARG"`;;
		u) only_uncompressed=1; display_option "build only the uncompressed ramdisk";;
		w) no_remount_ro=1; display_option "no remount ro in init.rc";;
		\?)
			echo "help!!!"
			exit 1
		;;
	esac
done

# check directories
if ! test -d $voodoo_ramdisk_parts || \
   ! test -n $dest || \
   ! test -d $source ; then
	echo "please specify 3 valid directories names"
	exit 1
fi

if ! test -n "$extentions_source" && ! test -d $extentions_source; then
	echo "please specify a valid extension source directory"
fi

echo -e "\nsource ramdisk:		$source"
echo "voodoo ramdisk parts:	$voodoo_ramdisk_parts"
echo "stages:			$stages_source"
echo "extensions:		$extentions_source"
echo -e "destination directory:	$dest\n"


make_cpio()
{
	echo "creating a cpio for $1"
	cd $1 || exit "error during stage cpio file creation"
	find | fakeroot cpio -H newc -o > ../$1.cpio
	ls -lh ../$1.cpio
	cd - >/dev/null
	echo 
}


optimize_cwm_directory()
{
	test -d cwm || return
	rm -rf cwm/META_INF
	rm -f cwm/res/sh
	rm -f cwm/sbin/fformat
	rm -f cwm/killrecovery.sh

	rm -f cwm/sbin/e2fsck
	ln -s /usr/sbin/e2fsck cwm/sbin/e2fsck

	rm -f cwm/sbin/tune2fs
	ln -s /usr/sbin/tune2fs cwm/sbin/tune2fs
}


activate_recovery_wrapper()
{
	sed 's/service recovery .*bin\/recovery/service recovery \/voodoo\/scripts\/recovery_wrapper.sh/' \
		recovery.rc > /tmp/recovery.rc
	sed 's/service console \/system\/bin\/sh//' /tmp/recovery.rc | \
		sed 's/.*console$//' > recovery.rc
}


activate_adbd_wrapper()
{
	sed 's/\/sbin\/adbd/\/voodoo\/scripts\/adbd_wrapper.sh/' recovery.rc > /tmp/recovery.rc
	cp /tmp/recovery.rc .
}


add_run_parts()
{
	rc_file=$1
	echo -e "\nservice run_parts /voodoo/scripts/run-parts.sh /system/etc/init.d" >> $rc_file
	echo -e "  oneshot \n" >> $rc_file
}


change_memory_management_settings()
{
	cat init.rc | \
	sed 's/FOREGROUND_APP_MEM.*/FOREGROUND_APP_MEM 2560/' | \
	sed 's/VISIBLE_APP_MEM.*/VISIBLE_APP_MEM 4096/' | \
	sed 's/SECONDARY_SERVER_MEM.*/SECONDARY_SERVER_MEM 6144/' | \
	sed 's/BACKUP_APP_MEM.*/BACKUP_APP_MEM 6144/' | \
	sed 's/HOME_APP_MEM.*/HOME_APP_MEM 6144/' | \
	sed 's/HIDDEN_APP_MEM.*/HIDDEN_APP_MEM 11264/' | \
	sed 's/CONTENT_PROVIDER_MEM.*/CONTENT_PROVIDER_MEM 13312/' | \
	sed 's/EMPTY_APP_MEM.*/EMPTY_APP_MEM 16384/' > /tmp/init.rc

	cat /tmp/init.rc | \
	sed 's/lowmemorykiller\/parameters\/minfree 2560,4096,6144,10240,11264,12288/lowmemorykiller\/parameters\/minfree 2560,4096,6144,11264,13312,16384/' > init.rc
}


tune_fs_options()
{
	# simply prevent lag from happening
	cat init.rc | \
	sed 's/dirty_expire_centisecs.*/dirty_expire_centisecs 800/' | \
	sed 's/dirty_background_ratio.*/dirty_background_ratio 2/' > /tmp/init.rc
	cp /tmp/init.rc init.rc
}


give_bootanimation_choice()
{
	# remove playslogo from init.rc, Voodoo lagfix boot script will make
	# start playslogo or bootanimation depending on what's on the phone
	cat init.rc | \
	sed 's/service playlogos1.*/service noplaylogos \/system\/bin\/false/' > /tmp/init.rc
	cp /tmp/init.rc init.rc
}

force_remount_system_ro()
{
	# remove playslogo from init.rc, Voodoo lagfix boot script will make
	# start playslogo or bootanimation depending on what's on the phone
	cat init.rc | \
	sed 's/\(mount.*\/dev\/block\/stl9.*\)/\1\n    mount ext4 \/dev\/block\/stl9 \/system remount ro/' > /tmp/init.rc
	cp /tmp/init.rc init.rc
}

# save the original running path
run_pwd=$PWD

# create the destination directory
mkdir -p $dest 2>/dev/null

# test if stage2 and at least stage3-sound exist
# FIXME: paths madness
if ! test -f $stages_source/stage2* || ! test -f $stages_source/stage3-sound*; then
	echo -e "\n\n # Error, please build the Voodoo lagfix stages first\n\n"
	exit 1
fi

# copy the ramdisk source to the voodoo ramdisk directory
cp -ax $source $dest/uncompressed
cd $dest/uncompressed || exit 1

# save working dir
working_dir=$PWD

mv init init_samsung

# change recovery.rc to call a wrapper instead of the real recovery binary
activate_recovery_wrapper

# add a wrapper to correct the adbd start issue (also on stock)
activate_adbd_wrapper

# change memory thresholds too Voodoo optimized ones
change_memory_management_settings

# vfs settings
tune_fs_options

# please :)
give_bootanimation_choice

# run-parts support
add_run_parts init.rc

# optimize CWM directory if it's there
optimize_cwm_directory

# be sure /system will be remounted as ro in normal boot
test "$no_remount_ro" != 1 && force_remount_system_ro

# copy ramdisk stuff
cd $run_pwd || exit 1
cp -a $voodoo_ramdisk_parts $working_dir/voodoo

# copy the extensions in voodoo/
test -n "$extentions_source" && cp -a $extentions_source $working_dir/voodoo/
cd $working_dir || exit 1


# empty directories, probably not in gits
mkdir dev 2>/dev/null
mkdir proc 2>/dev/null
mkdir sys 2>/dev/null
mkdir system 2>/dev/null
mkdir voodoo/tmp
mkdir voodoo/tmp/sdcard
mkdir voodoo/tmp/mnt
mkdir voodoo/root/usr


# symlink to voodoo stuff
ln -s voodoo/root/bin .
ln -s voodoo/root/usr .
# etc symlink will be used only during extraction of stages
# after that it needs to be removed
rm -f etc
ln -s voodoo/root/etc .
ln -s busybox bin/insmod
ln -s busybox bin/reboot


# create the main init symlink
ln -s voodoo/scripts/init_runner.sh init


# extract stage1 busybox
tar xf $stages_source/stage1.tar


# clean git stuff
find -name '.git*' -exec rm {} \;


# generate signatures for the stage
# because you want to be able to load them from the sdcard
for x in $stages_source/*.lzma; do
	sha1sum "$x" | cut -d' ' -f1 >> voodoo/signatures/`basename "$x" .tar.lzma`	
done


# copy the uncompressed ramdisk to the compressed before decompressing
# stage images in it
cd .. || exit 1
! test "$only_uncompressed" = 1 && cp -a uncompressed compressed


# do the uncompressed one
# extract stages directly
echo "Build the uncompressed ramdisk"
cd uncompressed || exit 1
for x in $stages_source/*.lzma; do
	lzcat "$x" | tar x
	> voodoo/run/`basename "$x" .tar.lzma`_loaded
done


# remove the etc symlink wich will causes problems when we boot
# directly on samsung_init
rm etc
cd .. || exit 1

make_cpio uncompressed

if test "$only_uncompressed" = 1; then
	echo "Building only uncompressed ramdisk"
	exit
fi


# do the smallest one. this one is wickely compressed!
echo "Build the compressed-smallest ramdisk"
cp -a uncompressed compressed-smallest
cd compressed-smallest || exit 1
rm voodoo/run/*
rm bin
rm init
echo '#!/bin/sh
export PATH=/bin

lzcat compressed_voodoo_ramdisk.tar.lzma | tar x
exec /voodoo/scripts/init_runner.sh' > init
chmod 755 init
mv voodoo/root/bin .

rm -r voodoo/voices
stage0_list="lib/ sbin/ voodoo/ cwm/ res/ modules/ *.rc init_samsung default.prop"
find $stage0_list 2>/dev/null | xargs tar c | lzma -9 > compressed_voodoo_ramdisk.tar.lzma
rm -r $stage0_list
cd .. || exit 1

make_cpio compressed-smallest


# do the compressed one
echo "Build the compressed ramdisk"
cp -a $stages_source/*.lzma compressed/voodoo/
cd compressed || exit 1
rm -r voodoo/voices
# important: remove the etc symlink
rm etc
cd .. || exit 1

make_cpio compressed


echo "Build the compressed-stage2-only"
cp -a compressed compressed-stage2-only
rm compressed-stage2-only/voodoo/stage3*

make_cpio compressed-stage2-only


echo
