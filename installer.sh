#!/sbin/sh
ui_print() {
	echo "ui_print $1" >"$OUTFD"
	echo "ui_print" >"$OUTFD"
}
set_progress() { echo "set_progress $1" >"$OUTFD"; }
creando_tmp() {
	TMP="/tmp"
	CORE_DIR="$TMP/SDK"
	REMOVER_FOLDER="$TMP/remover"
	REMOVER_SYS="$REMOVER_FOLDER/system"
	REMOVER_SYS_EXT="$REMOVER_FOLDER/system_ext"
	REMOVER_PR="$REMOVER_FOLDER/product"
	set_progress 0.10
}
#desmontando sistema y volviendo a montar
montando_sistema() {
	umount -l /system
	umount -l /system_root
	umount -l /system_ext
	umount -l /product
	umount -l /vendor
	system_as_root=$(getprop ro.build.system_root_image)
	active_slot=$(getprop ro.boot.slot_suffix)
	dynamic=$(getprop ro.boot.dynamic_partitions)
	ui_print "*                                                *"
	ui_print "*              MONTANDO PARTICIONES              *"
	sleep 1.0
	ui_print "*                                                *"
	if [ "$dynamic" = "true" ]; then
		ui_print "* - Particion dinamica detectada!                *"
		if [ ! -z "$active_slot" ]; then
			system_block=/dev/block/mapper/system$active_slot
			product_block=/dev/block/mapper/product$active_slot
			system_ext_block=/dev/block/mapper/system_ext$active_slot
			vendor_block=/dev/block/mapper/vendor$active_slot
		else
			system_block=/dev/block/mapper/system
			product_block=/dev/block/mapper/product
			system_ext_block=/dev/block/mapper/system_ext
			vendor_block=/dev/block/mapper/vendor
		fi
		blockdev --setrw $system_block
		blockdev --setrw $product_block
		blockdev --setrw $system_ext_block
		blockdev --setrw $vendor_block
	else
		if [ ! -z "$active_slot" ]; then
			system_block=$(cat /etc/recovery.fstab | grep -o '/dev/[^ ]*system' | cut -f -1 | head -1)$active_slot
			product_block=$(cat /etc/recovery.fstab | grep -o '/dev/[^ ]*product' | cut -f -1 | head -1)$active_slot
			ui_print "- SYSTEM: $system_block"
			if [ ! -z "$product_block" ]; then
				ui_print "- PRODUCT: $product_block"
			fi
		else
			system_block=$(cat /etc/recovery.fstab | grep -o '/dev/[^ ]*system' | cut -f -1 | head -1)
			product_block=$(cat /etc/recovery.fstab | grep -o '/dev/[^ ]*product' | cut -f -1 | head -1)
			ui_print "- SYSTEM: $system_block"
			if [ ! -z "$product_block" ]; then
				ui_print "- PRODUCT: $product_block"
			fi
		fi
	fi

	##### RESIZE PARTITIONS #####

	$TMP/e2fsck -fy $system_block
	$TMP/resize2fs $system_block
	sleep 1.0
	if [ ! -z "$product_block" ]; then
		$TMP/e2fsck -fy $product_block
		$TMP/resize2fs $product_block
		sleep 1.0
	fi

	if [ "$dynamic" = "true" ]; then
		$TMP/e2fsck -fy $system_ext_block
		$TMP/resize2fs $system_ext_block
	fi

	##### DETECT & MOUNT SYSTEM #####
	sleep 0.5
	mount_system() {
		mkdir -p /system
		mkdir -p /system_root
		if mount -o rw $system_block /system_root; then
			if [ -e /system_root/build.prop ]; then
				MOUNTED=/system_root
				ui_print "* - SYSTEM Detectado!                            *"
			else
				MOUNTED=/system_root/system
				ui_print "* - SYSTEM_ROOT Detectado!                       *"
			fi
			mount -o bind $MOUNTED /system
			SYSTEM=/system
			ui_print "* - SYSTEM Enlazado!                             *"
		else
			ui_print "* - No se pudo montar SYSTEM!                    *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
			umount -l /system && umount -l /system_root
			exit 1
		fi
	}

	mount_system
	sleep 0.5
	##### DETECT & MOUNT PRODUCT #####

	mkdir -p /product
	if [ -e $SYSTEM/product/build.prop ] || [ -e $SYSTEM/product/etc/build.prop ] || [ -e $SYSTEM/phh ]; then
		ui_print "| Using /system/product"
		PRODUCT=/system/product
	else
		if mount -o rw $product_block /product; then
			ui_print "* - PRODUCT Enlazado!                            *"
			PRODUCT=/product
		else
			ui_print "* - No se pudo montar PRODUCT!                   *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
		fi
	fi

	##### DETECT & MOUNT SYSTEM_EXT #####

	mkdir -p /system_ext
	if [ -e $SYSTEM/system_ext/build.prop ] || [ -e $SYSTEM/system_ext/etc/build.prop ] || [ -e $SYSTEM/phh ]; then
		SYSTEM_EXT=/system/system_ext
	else
		if mount -o rw $system_ext_block /system_ext; then
			ui_print "* - SYSTEM_EXT Enlazado!                         *"
			SYSTEM_EXT=/system_ext
		else
			ui_print "* - No se pudo montar SYSTEM_EXT!                *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
		fi
	fi
	mkdir -p /vendor
	if mount -o rw $vendor_block /vendor; then
		ui_print "* - VENDOR Enlazado!                             *"
		VENDOR=/vendor
	fi
	sleep 0.5
	set_progress 0.20

	OLD_LD_LIB=$LD_LIBRARY_PATH
	OLD_LD_PRE=$LD_PRELOAD
	OLD_LD_CFG=$LD_CONFIG_FILE
	unset LD_LIBRARY_PATH
	unset LD_PRELOAD
	unset LD_CONFIG_FILE
}
#version de android
android_version() {
	ui_print "*                                                *"
	ui_print "*        IDENTIFICANDO VERSION DE ANDROID        *"
	sleep 2.0
	ui_print "*                                                *"
	android_sdk=$(cat /system/build.prop | grep -o 'ro.system.build.version.sdk[^ ]*' | cut -c 29-30)
	#ui_print "- SDK: $android_sdk";
	if [ "$android_sdk" = 29 ]; then
		ui_print "* - Android 10                                   *"
	fi
	if [ "$android_sdk" = 30 ]; then
		ui_print "* - Android 11                                   *"
	fi
	if [ "$android_sdk" = 31 ]; then
		ui_print "* - Android 12                                   *"
	fi
	if [ "$android_sdk" = 32 ]; then
		ui_print "* - Android 12L                                  *"
	fi
	if [ "$android_sdk" = 33 ]; then
		ui_print "* - Android 13                                   *"
	fi
}
##limpiando rom
debloater() {
	ui_print "*                                                *"
	ui_print "*               LIMPIANDO ROM                    *"
	sleep 2.0
	ui_print "*                                                *"
	#esta lista es para apps de miui, más abajo encuentra la lista para aosp

	if [ -e $SYSTEM/app/miuisystem ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ]; then
		ui_print "* - Borrando apps en MIUI...                     *"
		if [ -e /data/data/com.miui.core ]; then
			rm -rf $PRODUCT/priv-app/PixelSetupWizard
			rm -rf $PRODUCT/priv-app/SetupWizard
			rm -rf $PRODUCT/priv-app/SetupWizardPrebuilt
			rm -rf $SYSTEM/priv-app/SetupWizard
			rm -rf $SYSTEM_EXT/priv-app/PixelSetupWizard
			rm -rf $SYSTEM_EXT/priv-app/SetupWizard
		fi
		#	rm -rf $SYSTEM/app/MIUIWeather
		#	rm -rf $SYSTEM/app/MIUIWeatherGlobal
		#	rm -rf $SYSTEM/app/Weather
		#	rm -rf $SYSTEM/priv-app/MIUIWeatherGlobal
		#rm -rf $PRODUCT/overlay/Monet*
		#rm -rf $SYSTEM/app/Calculator
		#rm -rf $SYSTEM/app/SogouInput
		#rm -rf $SYSTEM/app/Stk
		#rm -rf $SYSTEM/priv-app/MIUIWeather
		#rm -rf $SYSTEM/priv-app/Music
		#rm -rf $SYSTEM/priv-app/Weather
		rm -rf $PRODUCT/app/AiAsstVision
		rm -rf $PRODUCT/app/AndroidAutoStub
		rm -rf $PRODUCT/app/Backup
		rm -rf $PRODUCT/app/CarWith
		rm -rf $PRODUCT/app/Chrome
		rm -rf $PRODUCT/app/Chrome-Stub
		rm -rf $PRODUCT/app/CloudBackup
		rm -rf $PRODUCT/app/DevicePolicyPrebuilt
		rm -rf $PRODUCT/app/EmergencyInfo
		rm -rf $PRODUCT/app/FM
		rm -rf $PRODUCT/app/GlobalFashiongallery
		rm -rf $PRODUCT/app/Gmail2
		rm -rf $PRODUCT/app/GoogleAssistant
		rm -rf $PRODUCT/app/GoogleFeedback
		rm -rf $PRODUCT/app/GoogleOne
		rm -rf $PRODUCT/app/GoogleOneTimeInitializer
		rm -rf $PRODUCT/app/GooglePay
		rm -rf $PRODUCT/app/GoogleRestore
		rm -rf $PRODUCT/app/GoogleTTS
		rm -rf $PRODUCT/app/HybridAccessory
		rm -rf $PRODUCT/app/HybridPlatform
		rm -rf $PRODUCT/app/MINextpay
		rm -rf $PRODUCT/app/MITSMClient
		rm -rf $PRODUCT/app/MIUIAiasstService
		rm -rf $PRODUCT/app/MIUICloudService
		rm -rf $PRODUCT/app/MIUIMiCloudSync
		rm -rf $PRODUCT/app/MIUIReporter
		rm -rf $PRODUCT/app/MIUISecurityInputMethod
		rm -rf $PRODUCT/app/MIUISuperMarket
		rm -rf $PRODUCT/app/MIUIXiaomiAccount
		rm -rf $PRODUCT/app/MIpay
		rm -rf $PRODUCT/app/Maps
		rm -rf $PRODUCT/app/MiBugReport
		rm -rf $PRODUCT/app/MiuiCit
		rm -rf $PRODUCT/app/Notes
		rm -rf $PRODUCT/app/OmniJaws
		rm -rf $PRODUCT/app/PaymentService
		rm -rf $PRODUCT/app/PrebuiltGmail
		rm -rf $PRODUCT/app/SimActivateService
		rm -rf $PRODUCT/app/SogouInput
		rm -rf $PRODUCT/app/SpeechServicesByGoogle
		rm -rf $PRODUCT/app/Velvet
		rm -rf $PRODUCT/app/VoiceAssist
		rm -rf $PRODUCT/app/VoiceAssistAndroidT
		rm -rf $PRODUCT/app/VoiceTrigger
		rm -rf $PRODUCT/app/WellbeingPrebuilt
		rm -rf $PRODUCT/app/XPerienceWallpapers
		rm -rf $PRODUCT/app/XiaomiAccount
		rm -rf $PRODUCT/app/YouTube
		rm -rf $PRODUCT/app/aiasst_service
		rm -rf $PRODUCT/app/arcore
		rm -rf $PRODUCT/app/remoteSimLockAuthentication
		rm -rf $PRODUCT/app/talkback
		rm -rf $PRODUCT/app/uimremoteclient
		rm -rf $PRODUCT/app/uimremoteserver
		rm -rf $PRODUCT/data-app/Drive
		rm -rf $PRODUCT/data-app/Duo
		rm -rf $PRODUCT/data-app/GoogleNews
		rm -rf $PRODUCT/data-app/MIUISoundRecorderTargetSdk30
		rm -rf $PRODUCT/data-app/Photos
		rm -rf $PRODUCT/data-app/Podcasts
		rm -rf $PRODUCT/data-app/Videos
		rm -rf $PRODUCT/data-app/YTMusic
		rm -rf $PRODUCT/data-app/wps_lite
		rm -rf $PRODUCT/priv-app/AndroidAutoStub
		rm -rf $PRODUCT/priv-app/Backup
		rm -rf $PRODUCT/priv-app/Chrome
		rm -rf $PRODUCT/priv-app/CloudBackup
		rm -rf $PRODUCT/priv-app/EmergencyInfo
		rm -rf $PRODUCT/priv-app/GoogleAssistant
		rm -rf $PRODUCT/priv-app/GoogleFeedback
		rm -rf $PRODUCT/priv-app/GoogleOneTimeInitializer
		rm -rf $PRODUCT/priv-app/GoogleRestore
		rm -rf $PRODUCT/priv-app/GoogleRestorePrebuilt
		rm -rf $PRODUCT/priv-app/HelpRtcPrebuilt
		rm -rf $PRODUCT/priv-app/HotwordEnrollment*
		rm -rf $PRODUCT/priv-app/MIService
		rm -rf $PRODUCT/priv-app/MIShare
		rm -rf $PRODUCT/priv-app/MIUIBrowser
		rm -rf $PRODUCT/priv-app/MIUICloudBackup
		rm -rf $PRODUCT/priv-app/MIUIMusicT
		rm -rf $PRODUCT/priv-app/MIUIQuickSearchBox
		rm -rf $PRODUCT/priv-app/MIUIVideo
		rm -rf $PRODUCT/priv-app/MIUIYellowPage
		rm -rf $PRODUCT/priv-app/Notes
		rm -rf $PRODUCT/priv-app/NovaBugreportWrapper
		rm -rf $PRODUCT/priv-app/Velvet
		rm -rf $PRODUCT/priv-app/Wellbeing
		rm -rf $PRODUCT/priv-app/WellbeingPreBuilt
		rm -rf $PRODUCT/priv-app/WellbeingPrebuilt
		rm -rf $PRODUCT/priv-app/YouTube
		rm -rf $PRODUCT/priv-app/arcore
		rm -rf $PRODUCT/priv-app/ims
		rm -rf $SYSTEM/app/AbleMusic
		rm -rf $SYSTEM/app/AiAsstVision
		rm -rf $SYSTEM/app/AnalyticsCore
		rm -rf $SYSTEM/app/AndroidAutoStub
		rm -rf $SYSTEM/app/AntHalService
		rm -rf $SYSTEM/app/Backup
		rm -rf $SYSTEM/app/BasicDreams
		rm -rf $SYSTEM/app/BookmarkProvider
		rm -rf $SYSTEM/app/Browser
		rm -rf $SYSTEM/app/BugReport
		rm -rf $SYSTEM/app/BuiltInPrintService
		rm -rf $SYSTEM/app/CalculatorGlobalStub
		rm -rf $SYSTEM/app/CarrierDefaultApp
		rm -rf $SYSTEM/app/CatchLog
		rm -rf $SYSTEM/app/Cit
		rm -rf $SYSTEM/app/CloudPrint2
		rm -rf $SYSTEM/app/CloudService
		rm -rf $SYSTEM/app/CloudServiceSysbase
		rm -rf $SYSTEM/app/Compass
		rm -rf $SYSTEM/app/CompassGlobalStub
		rm -rf $SYSTEM/app/CovenantBR
		rm -rf $SYSTEM/app/EasterEgg
		rm -rf $SYSTEM/app/Email
		rm -rf $SYSTEM/app/EmergencyInfo
		rm -rf $SYSTEM/app/FidoAuthen
		rm -rf $SYSTEM/app/FidoClient
		rm -rf $SYSTEM/app/FrequentPhrase
		rm -rf $SYSTEM/app/GoogleAssistant
		rm -rf $SYSTEM/app/GoogleFeedback
		rm -rf $SYSTEM/app/GoogleOneTimeInitializer
		rm -rf $SYSTEM/app/GooglePrintRecommendationService
		rm -rf $SYSTEM/app/GoogleRestore
		rm -rf $SYSTEM/app/Health
		rm -rf $SYSTEM/app/HotwordEnrollmentOKGoogleWCD9340
		rm -rf $SYSTEM/app/HotwordEnrollmentXGoogleWCD9340
		rm -rf $SYSTEM/app/HybridAccessory
		rm -rf $SYSTEM/app/HybridPlatform
		rm -rf $SYSTEM/app/IdMipay
		rm -rf $SYSTEM/app/InMipay
		rm -rf $SYSTEM/app/Joyose
		rm -rf $SYSTEM/app/KSICibaEngine
		rm -rf $SYSTEM/app/Lens
		rm -rf $SYSTEM/app/LiveWallpapersPicker
		rm -rf $SYSTEM/app/MIDrop
		rm -rf $SYSTEM/app/MINextPay
		rm -rf $SYSTEM/app/MIRadioGlobalBuiltin
		rm -rf $SYSTEM/app/MIUICompassGlobal
		rm -rf $SYSTEM/app/MIUIMusicGlobal
		rm -rf $SYSTEM/app/MIUINotes
		rm -rf $SYSTEM/app/MIUISecurityInputMethod
		rm -rf $SYSTEM/app/MIUIVideoPlaye
		rm -rf $SYSTEM/app/MIUIVideoPlayer
		rm -rf $SYSTEM/app/MIUIXiaomiAccount
		rm -rf $SYSTEM/app/MSA
		rm -rf $SYSTEM/app/MSA-Global
		rm -rf $SYSTEM/app/MiBrowserGlobal
		rm -rf $SYSTEM/app/MiBugReport
		rm -rf $SYSTEM/app/MiCloudSync
		rm -rf $SYSTEM/app/MiDrive
		rm -rf $SYSTEM/app/MiDropStub
		rm -rf $SYSTEM/app/MiFitness
		rm -rf $SYSTEM/app/MiGalleryLockscreen
		rm -rf $SYSTEM/app/MiMoverGlobal
		rm -rf $SYSTEM/app/MiPicks
		rm -rf $SYSTEM/app/MiPlayClient
		rm -rf $SYSTEM/app/MiRadio
		rm -rf $SYSTEM/app/Mipay
		rm -rf $SYSTEM/app/MiuiAccessibility
		rm -rf $SYSTEM/app/MiuiAudioMonitor
		rm -rf $SYSTEM/app/MiuiBrowserGlobal
		rm -rf $SYSTEM/app/MiuiBugReport
		rm -rf $SYSTEM/app/MiuiCompass
		rm -rf $SYSTEM/app/MiuiDaemon
		rm -rf $SYSTEM/app/MiuiFreeformService
		rm -rf $SYSTEM/app/MiuiFrequentPhrase
		rm -rf $SYSTEM/app/MiuiGalleryGlobalExplore
		rm -rf $SYSTEM/app/MiuiGalleryLockscreen
		rm -rf $SYSTEM/app/MiuiPrintSpoolerBeta
		rm -rf $SYSTEM/app/MiuiScanner
		rm -rf $SYSTEM/app/Netflix_activation
		rm -rf $SYSTEM/app/NextPay
		rm -rf $SYSTEM/app/Notes
		rm -rf $SYSTEM/app/NotesGlobalStub
		rm -rf $SYSTEM/app/OneTimeInitializer
		rm -rf $SYSTEM/app/OsuLogin
		rm -rf $SYSTEM/app/PartnerBookmarksProvider
		rm -rf $SYSTEM/app/PaymentService
		rm -rf $SYSTEM/app/PersonalAssistant
		rm -rf $SYSTEM/app/PersonalAssistantGlobal
		rm -rf $SYSTEM/app/PlayAutoInstallStubApp
		rm -rf $SYSTEM/app/PrintRecommendationService
		rm -rf $SYSTEM/app/PrintSpooler
		rm -rf $SYSTEM/app/SolidExplorer
		rm -rf $SYSTEM/app/SolidExplorerUnlocker
		rm -rf $SYSTEM/app/TSMClient
		rm -rf $SYSTEM/app/TouchAssistant
		rm -rf $SYSTEM/app/Traceur
		rm -rf $SYSTEM/app/TranslationService
		rm -rf $SYSTEM/app/Turbo
		rm -rf $SYSTEM/app/UPTsmService
		rm -rf $SYSTEM/app/Velvet
		rm -rf $SYSTEM/app/VideoPlayer
		rm -rf $SYSTEM/app/Videos
		rm -rf $SYSTEM/app/VoiceAssist
		rm -rf $SYSTEM/app/VoiceAssistant
		rm -rf $SYSTEM/app/VoiceTrigger
		rm -rf $SYSTEM/app/VsimCore
		rm -rf $SYSTEM/app/WAPPushManager
		rm -rf $SYSTEM/app/WMServices
		rm -rf $SYSTEM/app/WellbeingPrebuilt
		rm -rf $SYSTEM/app/XMCloudEngine
		rm -rf $SYSTEM/app/XMSFKeeper
		rm -rf $SYSTEM/app/XPeriaWeather
		rm -rf $SYSTEM/app/XiaomiAccount
		rm -rf $SYSTEM/app/XiaomiSimActivateService
		rm -rf $SYSTEM/app/YTProMicrog
		rm -rf $SYSTEM/app/YouDaoEngine
		rm -rf $SYSTEM/app/YouTube
		rm -rf $SYSTEM/app/YoutubeVanced
		rm -rf $SYSTEM/app/Yunikon
		rm -rf $SYSTEM/app/arcore
		rm -rf $SYSTEM/app/com.miui.qr
		rm -rf $SYSTEM/app/com.xiaomi.macro
		rm -rf $SYSTEM/app/facebook
		rm -rf $SYSTEM/app/facebook-appmanager
		rm -rf $SYSTEM/app/greenguard
		rm -rf $SYSTEM/app/mab
		rm -rf $SYSTEM/app/mi_connect_service
		rm -rf $SYSTEM/app/wps-lite
		rm -rf $SYSTEM/app/wps_lite
		rm -rf $SYSTEM/data-app/Gmail2
		rm -rf $SYSTEM/data-app/MIBrowserGlobal
		rm -rf $SYSTEM/data-app/MIGalleryLockScreen
		rm -rf $SYSTEM/data-app/MIGalleryLockScreenGlobal
		rm -rf $SYSTEM/data-app/MIGalleryLockscreen
		rm -rf $SYSTEM/data-app/MIGalleryLockscreenGlobal
		rm -rf $SYSTEM/data-app/MIMediaEditorGlobal
		rm -rf $SYSTEM/data-app/MIUICompass
		rm -rf $SYSTEM/data-app/MIUICompassGlobal
		rm -rf $SYSTEM/data-app/MIUISoundRecorderTargetSdk30
		rm -rf $SYSTEM/data-app/MIUISoundRecorderTargetSdk30Global
		rm -rf $SYSTEM/data-app/MIUISuperMarket
		rm -rf $SYSTEM/data-app/MiCreditInStub
		rm -rf $SYSTEM/data-app/MiRemote
		rm -rf $SYSTEM/data-app/ShareMe
		rm -rf $SYSTEM/data-app/XMRemoteController
		rm -rf $SYSTEM/etc/yellowpage
		rm -rf $SYSTEM/priv-app/AnalyticsCore
		rm -rf $SYSTEM/priv-app/AndroidAutoStub
		rm -rf $SYSTEM/priv-app/AntHalService
		rm -rf $SYSTEM/priv-app/Backup
		rm -rf $SYSTEM/priv-app/BasicDreams
		rm -rf $SYSTEM/priv-app/BookmarkProvider
		rm -rf $SYSTEM/priv-app/Browser
		rm -rf $SYSTEM/priv-app/BugReport
		rm -rf $SYSTEM/priv-app/BuiltInPrintService
		rm -rf $SYSTEM/priv-app/CatchLog
		rm -rf $SYSTEM/priv-app/CellBroadcastServiceModulePlatform
		rm -rf $SYSTEM/priv-app/Cit
		rm -rf $SYSTEM/priv-app/CloudBackup
		rm -rf $SYSTEM/priv-app/CloudPrint2
		rm -rf $SYSTEM/priv-app/CloudService
		rm -rf $SYSTEM/priv-app/CloudServiceSysbase
		rm -rf $SYSTEM/priv-app/EmergencyInfo
		rm -rf $SYSTEM/priv-app/GameCenterGlobal
		rm -rf $SYSTEM/priv-app/GlobalMinusScreen
		rm -rf $SYSTEM/priv-app/GoogleAssistant
		rm -rf $SYSTEM/priv-app/GoogleFeedback
		rm -rf $SYSTEM/priv-app/GoogleOneTimeInitializer
		rm -rf $SYSTEM/priv-app/GoogleRestore
		rm -rf $SYSTEM/priv-app/GoogleTTS
		rm -rf $SYSTEM/priv-app/HotwordEnrollmentOKGoogleWCD9340
		rm -rf $SYSTEM/priv-app/HotwordEnrollmentXGoogleWCD9340
		rm -rf $SYSTEM/priv-app/MIService
		rm -rf $SYSTEM/priv-app/MIShareGlobal
		rm -rf $SYSTEM/priv-app/MIUISoundRecorderTargetSdk30Global
		rm -rf $SYSTEM/priv-app/MIUIYellowPageGlobal
		rm -rf $SYSTEM/priv-app/MiBrowser
		rm -rf $SYSTEM/priv-app/MiBrowserGlobal
		rm -rf $SYSTEM/priv-app/MiCloudSync
		rm -rf $SYSTEM/priv-app/MiDrive
		rm -rf $SYSTEM/priv-app/MiDrop
		rm -rf $SYSTEM/priv-app/MiGame
		rm -rf $SYSTEM/priv-app/MiGameCenterSDKService
		rm -rf $SYSTEM/priv-app/MiMover
		rm -rf $SYSTEM/priv-app/MiMoverGlobal
		rm -rf $SYSTEM/priv-app/MiPlayClient
		rm -rf $SYSTEM/priv-app/MiService
		rm -rf $SYSTEM/priv-app/MiShare
		rm -rf $SYSTEM/priv-app/MiuiBrowser
		rm -rf $SYSTEM/priv-app/MiuiBrowserGlobal
		rm -rf $SYSTEM/priv-app/MiuiBugReport
		rm -rf $SYSTEM/priv-app/MiuiFreeformService
		rm -rf $SYSTEM/priv-app/MiuiHealth
		rm -rf $SYSTEM/priv-app/MiuiMusic
		rm -rf $SYSTEM/priv-app/MiuiScanner
		rm -rf $SYSTEM/priv-app/MiuiVideo
		rm -rf $SYSTEM/priv-app/MusicFX
		rm -rf $SYSTEM/priv-app/NewHome
		rm -rf $SYSTEM/priv-app/Notes
		rm -rf $SYSTEM/priv-app/ONS
		rm -rf $SYSTEM/priv-app/OneTimeInitializer
		rm -rf $SYSTEM/priv-app/PartnerBookmarksProvider
		rm -rf $SYSTEM/priv-app/PersonalAssistant
		rm -rf $SYSTEM/priv-app/PersonalAssistantGlobal
		rm -rf $SYSTEM/priv-app/PrintRecommendationService
		rm -rf $SYSTEM/priv-app/ProxyHandler
		rm -rf $SYSTEM/priv-app/QuickSearchBox
		rm -rf $SYSTEM/priv-app/ScannerGlobalStub
		rm -rf $SYSTEM/priv-app/SoundRecorder
		rm -rf $SYSTEM/priv-app/SoundRecorderStub
		rm -rf $SYSTEM/priv-app/SoundRecorderTargetSdk30
		rm -rf $SYSTEM/priv-app/Tag
		rm -rf $SYSTEM/priv-app/Turbo
		rm -rf $SYSTEM/priv-app/UserDictionaryProvider
		rm -rf $SYSTEM/priv-app/Velvet
		rm -rf $SYSTEM/priv-app/Videos
		rm -rf $SYSTEM/priv-app/VoiceCommand
		rm -rf $SYSTEM/priv-app/VoiceTrigger
		rm -rf $SYSTEM/priv-app/VoiceUnlock
		rm -rf $SYSTEM/priv-app/WellbeingPreBuilt
		rm -rf $SYSTEM/priv-app/WellbeingPrebuilt
		rm -rf $SYSTEM/priv-app/YellowPage
		rm -rf $SYSTEM/priv-app/YouTube
		rm -rf $SYSTEM/priv-app/arcore
		rm -rf $SYSTEM/priv-app/facebook
		rm -rf $SYSTEM/priv-app/facebook-installer
		rm -rf $SYSTEM/priv-app/facebook-services
		rm -rf $SYSTEM/system/product/priv-app/QtiSoundRecorder
		rm -rf $SYSTEM/vendor/app/Joyose
		rm -rf $SYSTEM/vendor/app/SoterService
		rm -rf $SYSTEM/vendor/data/app/Drive
		rm -rf $SYSTEM/vendor/data/app/Duo
		rm -rf $SYSTEM/vendor/data/app/Music2
		rm -rf $SYSTEM/vendor/data/app/Photos
		rm -rf $SYSTEM/vendor/data/app/XMRemoteController
		rm -rf $SYSTEM/vendor/data/app/wps_lite
		rm -rf $SYSTEM_EXT/app/FM
		rm -rf $SYSTEM_EXT/app/Papers
		rm -rf $SYSTEM_EXT/priv-app/EmergencyInfo
		rm -rf $SYSTEM_EXT/priv-app/GoogleFeedback
		rm -rf $SYSTEM_EXT/priv-app/Leaflet
		rm -rf $SYSTEM_EXT/priv-app/MatLogrm#
		#
		#
		#
		#debloat  para AOSP
		#
		#
		#
		sleep 2.0
	elif [ -e /system_root/my_stock ]; then #debloat para oxigen
		SYSTEM_ROOT="/system_root"
		ui_print "* - Borrando apps en OxigenOS...                 *"
		rm -rf $SYSTEM_EXT/app/LogKit
		rm -rf $SYSTEM_EXT/app/Olc
		rm -rf $SYSTEM_ROOT/my_heytap/app/ARCore
		rm -rf $SYSTEM_ROOT/my_heytap/app/Chrome
		rm -rf $SYSTEM_ROOT/my_heytap/app/Music
		rm -rf $SYSTEM_ROOT/my_heytap/app/SpeechServicesByGoogle
		rm -rf $SYSTEM_ROOT/my_heytap/app/talkback
		rm -rf $SYSTEM_ROOT/my_heytap/non_overlay/priv-app/SetupWizard
		rm -rf $SYSTEM_ROOT/my_heytap/priv-app/AndroidAutoStub
		rm -rf $SYSTEM_ROOT/my_heytap/priv-app/GoogleRestore
		rm -rf $SYSTEM_ROOT/my_heytap/priv-app/Velvet
		rm -rf $SYSTEM_ROOT/my_heytap/priv-app/Wellbeing
		rm -rf $SYSTEM_ROOT/my_stock/app/ChildrenSpace
		rm -rf $SYSTEM_ROOT/my_stock/app/OPlusSegurityKeyboard
		rm -rf $SYSTEM_ROOT/my_stock/app/OplusOperationManual
		rm -rf $SYSTEM_ROOT/my_stock/del-app/OPBreathMode
		rm -rf $SYSTEM_ROOT/my_stock/del-app/OPNote
		rm -rf $SYSTEM_ROOT/my_stock/priv-app/KeKeUserCenter
		rm -rf $SYSTEM_ROOT/my_stock/priv-app/SOSHelper
		rm -rf $SYSTEM_ROOT/my_bigball/app/Omoji
		rm -rf $SYSTEM_ROOT/my_product/app/HotwordEnrollment*.apk
		sleep 2.0
	else
		ui_print "* - Borrando apps en AOSP...                     *"
		rm -rf $PRODUCT/app/AboutBliss
		rm -rf $PRODUCT/app/Abstruct
		rm -rf $PRODUCT/app/BasicDreams
		rm -rf $PRODUCT/app/BlissStatistics
		rm -rf $PRODUCT/app/BookmarkProvider
		rm -rf $PRODUCT/app/Bromite
		rm -rf $PRODUCT/app/Browser
		rm -rf $PRODUCT/app/Calendar
		rm -rf $PRODUCT/app/Chrome
		rm -rf $PRODUCT/app/Chrome-Stub
		rm -rf $PRODUCT/app/Dashboard
		rm -rf $PRODUCT/app/DevicePolicyPrebuilt
		rm -rf $PRODUCT/app/Drive
		rm -rf $PRODUCT/app/EasterEgg
		rm -rf $PRODUCT/app/Email
		rm -rf $PRODUCT/app/EmergencyInfo
		rm -rf $PRODUCT/app/Etar
		rm -rf $PRODUCT/app/ExactCalculator
		rm -rf $PRODUCT/app/Exchange2
		rm -rf $PRODUCT/app/FM2
		rm -rf $PRODUCT/app/Gallery
		rm -rf $PRODUCT/app/Gallery2
		rm -rf $PRODUCT/app/GalleryGoPrebuilt
		rm -rf $PRODUCT/app/GoogleTTS
		rm -rf $PRODUCT/app/GrapheneCamera
		rm -rf $PRODUCT/app/Jelly
		rm -rf $PRODUCT/app/Maps
		rm -rf $PRODUCT/app/Music
		rm -rf $PRODUCT/app/OPWidget
		rm -rf $PRODUCT/app/PartnerBookmark
		rm -rf $PRODUCT/app/Partnerbookmark
		rm -rf $PRODUCT/app/PhotoTable
		rm -rf $PRODUCT/app/Photos
		rm -rf $PRODUCT/app/PrebuiltGmail
		rm -rf $PRODUCT/app/QPGallery
		rm -rf $PRODUCT/app/QtiSoundRecorder
		rm -rf $PRODUCT/app/Recorder
		rm -rf $PRODUCT/app/RetroMusic
		rm -rf $PRODUCT/app/RetroMusicPlayer
		rm -rf $PRODUCT/app/SimpleGallery
		rm -rf $PRODUCT/app/Tycho
		rm -rf $PRODUCT/app/Velvet
		rm -rf $PRODUCT/app/Via
		rm -rf $PRODUCT/app/Videos
		rm -rf $PRODUCT/app/WallpaperZone
		rm -rf $PRODUCT/app/WallpapersBReel2020
		rm -rf $PRODUCT/app/WallpapersBReel2020a
		rm -rf $PRODUCT/app/WellbeingPrebuilt
		rm -rf $PRODUCT/app/XPerienceWallpapers
		rm -rf $PRODUCT/app/YouTube
		rm -rf $PRODUCT/app/YouTubeMusicPrebuilt
		rm -rf $PRODUCT/app/arcore
		rm -rf $PRODUCT/app/crDroidMusic
		rm -rf $PRODUCT/app/talkback
		rm -rf $PRODUCT/overlay/ChromeOverlay
		rm -rf $PRODUCT/overlay/TelegramOverlay
		rm -rf $PRODUCT/overlay/WhatsAppOverlay
		rm -rf $PRODUCT/priv-app/AncientWallpaperZone
		rm -rf $PRODUCT/priv-app/AndroidAutoStub
		rm -rf $PRODUCT/priv-app/AndroidAutoStubPrebuilt
		rm -rf $PRODUCT/priv-app/AndroidMigratePrebuilt
		rm -rf $PRODUCT/priv-app/Chrome
		rm -rf $PRODUCT/priv-app/DuckDuckGo
		rm -rf $PRODUCT/priv-app/Eleven
		rm -rf $PRODUCT/priv-app/Email
		rm -rf $PRODUCT/priv-app/EmergencyInfo
		rm -rf $PRODUCT/priv-app/FM2
		rm -rf $PRODUCT/priv-app/Gallery2
		rm -rf $PRODUCT/priv-app/GoogleRestore
		rm -rf $PRODUCT/priv-app/GoogleRestorePrebuilt
		rm -rf $PRODUCT/priv-app/HelpRtcPrebuilt
		rm -rf $PRODUCT/priv-app/HotwordEnrollmentOKGoogleHEXAGON
		rm -rf $PRODUCT/priv-app/HotwordEnrollmentXGoogleHEXAGON
		rm -rf $PRODUCT/priv-app/MatLog
		rm -rf $PRODUCT/priv-app/MusicFX
		rm -rf $PRODUCT/priv-app/NovaBugreportWrapper
		rm -rf $PRODUCT/priv-app/OmniSwitch
		rm -rf $PRODUCT/priv-app/PixelLiveWallpaperPrebuilt
		rm -rf $PRODUCT/priv-app/PixelSetupWizard
		rm -rf $PRODUCT/priv-app/QtiSoundRecorder
		rm -rf $PRODUCT/priv-app/RecorderPrebuilt
		rm -rf $PRODUCT/priv-app/RetroMusicPlayer
		rm -rf $PRODUCT/priv-app/SafetyHub
		rm -rf $PRODUCT/priv-app/SafetyHubPrebuilt
		rm -rf $PRODUCT/priv-app/ScribePrebuilt
		rm -rf $PRODUCT/priv-app/SetupWizard
		rm -rf $PRODUCT/priv-app/SetupWizardPrebuilt
		rm -rf $PRODUCT/priv-app/SimpleCalendar
		rm -rf $PRODUCT/priv-app/SimpleGallery
		rm -rf $PRODUCT/priv-app/Snap
		rm -rf $PRODUCT/priv-app/Tag
		rm -rf $PRODUCT/priv-app/TipsPrebuilt
		rm -rf $PRODUCT/priv-app/Velvet
		rm -rf $PRODUCT/priv-app/Via
		rm -rf $PRODUCT/priv-app/ViaBrowser
		rm -rf $PRODUCT/priv-app/VinylMusicPlayer
		rm -rf $PRODUCT/priv-app/Wellbeing
		rm -rf $PRODUCT/priv-app/WellbeingPrebuilt
		rm -rf $PRODUCT/priv-app/arcore
		rm -rf $PRODUCT/priv-app/crDroidMusic
		rm -rf $PRODUCT/priv-app/stats
		rm -rf $SYSTEM/app/AbleMusic
		rm -rf $SYSTEM/app/Abstruct
		rm -rf $SYSTEM/app/Aves
		rm -rf $SYSTEM/app/BasicDreams
		rm -rf $SYSTEM/app/BlissPapers
		rm -rf $SYSTEM/app/BlissUpdater
		rm -rf $SYSTEM/app/BookmarkProvider
		rm -rf $SYSTEM/app/Browser
		rm -rf $SYSTEM/app/Chromium
		rm -rf $SYSTEM/app/CloudPrint
		rm -rf $SYSTEM/app/ColtPapers
		rm -rf $SYSTEM/app/DuckDuckGo
		rm -rf $SYSTEM/app/EggGame
		rm -rf $SYSTEM/app/Email
		rm -rf $SYSTEM/app/Exchange2
		rm -rf $SYSTEM/app/FM2
		rm -rf $SYSTEM/app/Gallery
		rm -rf $SYSTEM/app/GugelClock
		rm -rf $SYSTEM/app/Jelly
		rm -rf $SYSTEM/app/Kiwi
		rm -rf $SYSTEM/app/MiXplorer
		rm -rf $SYSTEM/app/Music
		rm -rf $SYSTEM/app/PartnerBookmark
		rm -rf $SYSTEM/app/Partnerbookmark
		rm -rf $SYSTEM/app/Phonograph
		rm -rf $SYSTEM/app/PhotoTable
		rm -rf $SYSTEM/app/QPGallery
		rm -rf $SYSTEM/app/RetroMusic
		rm -rf $SYSTEM/app/RetroMusicPlayer
		rm -rf $SYSTEM/app/RetroMusicPlayerPrebuilt
		rm -rf $SYSTEM/app/SimpleCalendar
		rm -rf $SYSTEM/app/SimpleGallery
		rm -rf $SYSTEM/app/StagWalls
		rm -rf $SYSTEM/app/Superiorwalls
		rm -rf $SYSTEM/app/TilesWallpaper
		rm -rf $SYSTEM/app/VanillaMusic
		rm -rf $SYSTEM/app/Velvet
		rm -rf $SYSTEM/app/Via
		rm -rf $SYSTEM/app/ViaBrowser
		rm -rf $SYSTEM/app/WellbeingPrebuilt
		rm -rf $SYSTEM/app/Yunikon
		rm -rf $SYSTEM/app/arcore
		rm -rf $SYSTEM/app/crDroidMusic
		rm -rf $SYSTEM/priv-app/AudioFX
		rm -rf $SYSTEM/priv-app/BlissUpdater
		rm -rf $SYSTEM/priv-app/Calendar
		rm -rf $SYSTEM/priv-app/Eleven
		rm -rf $SYSTEM/priv-app/Email
		rm -rf $SYSTEM/priv-app/FM2
		rm -rf $SYSTEM/priv-app/Gallery2
		rm -rf $SYSTEM/priv-app/MatLog
		rm -rf $SYSTEM/priv-app/MetroMusicPlayer
		rm -rf $SYSTEM/priv-app/MusicFX
		rm -rf $SYSTEM/priv-app/OmniSwitch
		rm -rf $SYSTEM/priv-app/RetroMusicPlayerPrebuilt
		rm -rf $SYSTEM/priv-app/SetupWizard
		rm -rf $SYSTEM/priv-app/Snap
		rm -rf $SYSTEM/priv-app/Tag
		rm -rf $SYSTEM/priv-app/Velvet
		rm -rf $SYSTEM/priv-app/Via
		rm -rf $SYSTEM/priv-app/VinylMusicPlayer
		rm -rf $SYSTEM/priv-app/WellbeingPrebuilt
		rm -rf $SYSTEM/priv-app/arcore
		rm -rf $SYSTEM/priv-app/crDroidMusic
		rm -rf $SYSTEM/priv-app/stats
		rm -rf $SYSTEM_EXT/app/EmergencyInfo
		rm -rf $SYSTEM_EXT/app/FM2
		rm -rf $SYSTEM_EXT/app/Papers
		rm -rf $SYSTEM_EXT/app/Photos
		rm -rf $SYSTEM_EXT/app/Superiorwalls
		rm -rf $SYSTEM_EXT/priv-app/AndroidAutoStubPrebuilt
		rm -rf $SYSTEM_EXT/priv-app/AudioFX
		rm -rf $SYSTEM_EXT/priv-app/EmergencyInfo
		rm -rf $SYSTEM_EXT/priv-app/FM2
		rm -rf $SYSTEM_EXT/priv-app/Gallery2
		rm -rf $SYSTEM_EXT/priv-app/GoogleRestore
		rm -rf $SYSTEM_EXT/priv-app/Leaflet
		rm -rf $SYSTEM_EXT/priv-app/MatLog
		rm -rf $SYSTEM_EXT/priv-app/Music
		rm -rf $SYSTEM_EXT/priv-app/PixelSetupWizard
		rm -rf $SYSTEM_EXT/priv-app/SetupWizard
		rm -rf $SYSTEM_EXT/priv-app/Snap
		rm -rf $SYSTEM_EXT/priv-app/Updates
		rm -rf $SYSTEM_EXT/priv-app/WellbeingPrebuilt
		rm -rf $SYSTEM_EXT/priv-app/PixelSetupWizard
		rm -rf $PRODUCT/app/GalleryGo
		sleep 2.0
	fi
	set_progress 0.30
}
photo() {
	rm -rf $PRODUCT/etc/sysconfig/google_exclusives_enable.xml
	rm -rf $SYSTEM/etc/sysconfig/google_exclusives_enable.xml
	rm -rf $SYSTEM/etc/sysconfig/Shift.xml
	rm -rf $SYSTEM/etc/sysconfig/Notice
	rm -rf $PRODUCT/etc/sysconfig/Shift.xml
	rm -rf $PRODUCT/etc/sysconfig/Notice
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $PRODUCT/etc/sysconfig/nga.xml
	#rm -rf $PRODUCT/etc/sysconfig/nexus.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $SYSTEM/etc/sysconfig/nga.xml
	rm -rf $SYSTEM/etc/sysconfig/nexus.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/nga.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/nexus.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2022_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2022_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2022.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2022.xml
}
##descomprimiendo sdktotal
herramientas() {
	ui_print "* - Preparando herramientas...                   *"
	mkdir $TMP/remover
	chmod 0755 $TMP/remover
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP
	set_progress 0.40
	###descomprimiendo archivos
	tar -xf "$CORE_DIR/SDKTOTAL.tar.xz" -C $REMOVER_FOLDER
	if [ $rem -eq 0 ]; then
		if [ $a -gt 10 ]; then
			echo "$a is even number and greater than 10."

		else
			echo "$a is even number and less than 10."
		fi
	else
		echo "$a is odd number"
	fi
	if [ -e $PRODUCT/etc/sysconfig/google_elite_configs.xml ]; then
		rm -rf $PRODUCT/etc/sysconfig/google_elite_configs.xml
	else
		rm -rf $REMOVER_PR/etc/sysconfig/google_elite_configs.xml
	fi
	sleep 2.0
}
pre_swizard() {
	##esto es para miui
	if [ -e $SYSTEM/app/miuisystem ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ]; then
		rm -rf $REMOVER_PR/overlay
	##esto si es aosp
	else
		##EXTRAYENDO SETUP-PROVIDER
		if [ "$android_sdk" = 29 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/TTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/STheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/SLTheGapps-Provision.apk
		fi
		if [ "$android_sdk" = 30 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/STheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/SLTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/TTheGapps-Provision.apk
		fi
		if [ "$android_sdk" = 31 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/TTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/RTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/SLTheGapps-Provision.apk
		fi
		if [ "$android_sdk" = 32 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/TTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/RTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/STheGapps-Provision.apk
			fixrice() {
				if [ -e $PRODUCT/app/riceDroidThemesStub ] || [ -e $PRODUCT/app/crDroidThemesStub ]; then
					rm -rf $PRODUCT/priv-app/DevicePersonalizationPrebuiltPixel2021
				fi
			}
			fixrice
		fi
		if [ "$android_sdk" = 33 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/RTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/STheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/SLTheGapps-Provision.apk
		fi
	fi
}
files() {
	#ui_print "- Instalando mods en system..."
	sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_list; do
		install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
		chmod 0644 "$SYSTEM/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
	done

	for dir in $sys_dir_list; do
		chmod 0755 "$SYSTEM/${dir}"
	done

	#ui_print "- Instalando mods en system_ext..."
	sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_ext_list; do
		install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
		chmod 0644 "$SYSTEM_EXT/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
	done

	for dir in $sys_ext_dir_list; do
		chmod 0755 "$SYSTEM_EXT/${dir}"
	done

	#ui_print "- Instalando mods en product..."
	pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
	pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $pr_list; do
		install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
		chmod 0644 "$PRODUCT/${file}"
		chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
	done

	for dir in $pr_dir_list; do
		chmod 0755 "$PRODUCT/${dir}"
	done
}
swizard() {
	#Aplicando lineas al build para omitir setupwizard
	echo -e "ro.setupwizard.mode=DISABLED" >>"$SYSTEM_EXT/etc/build.prop"
	sed -i '/^ro.setupwizard.enterprise_mode/d' "$PRODUCT/etc/build.prop"
	sed -i '/^setupwizard.feature.baseline_setupwizard_enabled/d' "$PRODUCT/etc/build.prop"
	echo -e "ro.setupwizard.mode=DISABLED" >>"$SYSTEM_EXT/build.prop"
	if [ "$android_sdk" = 29 ]; then
		chcon -h u:object_r:vendor_overlay_file:s0 "$PRODUCT/overlay/RTheGapps-Provision.apk"
	fi
	if [ "$android_sdk" = 30 ]; then
		chcon -h u:object_r:vendor_overlay_file:s0 "$PRODUCT/overlay/RTheGapps-Provision.apk"
	fi
	if [ "$android_sdk" = 31 ]; then
		chcon -h u:object_r:vendor_overlay_file:s0 "$PRODUCT/overlay/STheGapps-Provision.apk"
	fi
	if [ "$android_sdk" = 32 ]; then
		chcon -h u:object_r:vendor_overlay_file:s0 "$PRODUCT/overlay/SLTheGapps-Provision.apk"
	fi
	if [ "$android_sdk" = 33 ]; then
		chcon -h u:object_r:vendor_overlay_file:s0 "$PRODUCT/overlay/TTheGapps-Provision.apk"
	fi
}
pl() {

	rm -rf $REMOVER_FOLDER
	mkdir $TMP/remover
	chmod 0755 $TMP/remover
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP
	if [ -e $SYSTEM/app/miuisystem ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ] || [ -e $SYSTEM_ROOT/my_stock ]; then
		rm -rf $CORE_DIR/SDKPL.tar.xz
		rm -rf $CORE_DIR/SDKPL13.tar.xz
	else
		if [ "$android_sdk" = 32 ]; then
			ui_print "* - Instalando Pixel Launcher v11.6...           *"
			echo -e "ro.boot.vendor.overlay.static=false" >>"$SYSTEM/build.prop"
			rm -rf $PRODUCT/overlay/PixelLauncherCustomOverlay
			rm -rf $PRODUCT/overlay/ThemedIconsOverlay
			rm -rf $PRODUCT/overlay/PixelLauncherIconsOverlay
			rm -rf $PRODUCT/overlay/PixelRecentsProvider
			rm -rf $SYSTEM_EXT/priv-app/NexusLauncherRelease
			rm -rf $PRODUCT/app/Lawnfeed
			rm -rf $PRODUCT/app/Lawnicons
			rm -rf $SYSTEM/priv-app/AsusLauncherDev
			rm -rf $SYSTEM/priv-app/Lawnchair
			rm -rf $SYSTEM/priv-app/NexusLauncherPrebuilt
			rm -rf $PRODUCT/priv-app/ParanoidQuickStep
			rm -rf $PRODUCT//priv-app/ShadyQuickStep
			rm -rf $PRODUCT/priv-app/TrebuchetQuickStep
			rm -rf $PRODUCT/priv-app/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/priv-app/DerpLauncherQuickStep
			rm -rf $SYSTEM_EXT/priv-app/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/priv-app/TrebuchetQuickStep
			rm -rf $SYSTEM_EXT/priv-app/Lawnchair
			rm -rf $SYSTEM_EXT/priv-app/Launcher3QuickStep
			tar -xf "$CORE_DIR/SDKPL.tar.xz" -C $REMOVER_FOLDER
			sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
			sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $sys_list; do
				install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
				chmod 0644 "$SYSTEM/${file}"
				chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
			done

			for dir in $sys_dir_list; do
				chmod 0755 "$SYSTEM/${dir}"
			done

			#ui_print "- Instalando mods en system_ext..."
			sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
			sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $sys_ext_list; do
				install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
				chmod 0644 "$SYSTEM_EXT/${file}"
				chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
			done

			for dir in $sys_ext_dir_list; do
				chmod 0755 "$SYSTEM_EXT/${dir}"
			done

			#ui_print "- Instalando mods en product..."
			pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
			pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $pr_list; do
				install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
				chmod 0644 "$PRODUCT/${file}"
				chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
			done

			for dir in $pr_dir_list; do
				chmod 0755 "$PRODUCT/${dir}"
			done
			sleep 2.0
		else
			rm -rf $CORE_DIR/SDKPL.tar.xz
		fi
		if [ "$android_sdk" = 33 ]; then
			ui_print "* - Instalando Pixel Launcher v13...             *"
			echo -e "ro.boot.vendor.overlay.static=false" >>"$SYSTEM/build.prop"
			rm -rf $PRODUCT/overlay/PixelLauncherCustomOverlay
			rm -rf $PRODUCT/overlay/ThemedIconsOverlay
			rm -rf $PRODUCT/overlay/PixelLauncherIconsOverlay
			rm -rf $PRODUCT/overlay/PixelRecentsProvider
			rm -rf $SYSTEM_EXT/priv-app/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/priv-app/ThemePicker
			rm -rf $PRODUCT/app/Lawnfeed
			rm -rf $PRODUCT/app/Lawnicons
			rm -rf $SYSTEM/priv-app/AsusLauncherDev
			rm -rf $SYSTEM/priv-app/Lawnchair
			rm -rf $SYSTEM/priv-app/NexusLauncherPrebuilt
			rm -rf $PRODUCT/priv-app/ParanoidQuickStep
			rm -rf $PRODUCT//priv-app/ShadyQuickStep
			rm -rf $PRODUCT/priv-app/TrebuchetQuickStep
			rm -rf $PRODUCT/priv-app/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/priv-app/DerpLauncherQuickStep
			rm -rf $SYSTEM_EXT/priv-app/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/priv-app/TrebuchetQuickStep
			rm -rf $SYSTEM_EXT/priv-app/Lawnchair
			rm -rf $SYSTEM_EXT/priv-app/Launcher3QuickStep
			tar -xf "$CORE_DIR/SDKPL13.tar.xz" -C $REMOVER_FOLDER

			#ui_print "- Instalando mods en system..."
			sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
			sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $sys_list; do
				install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
				chmod 0644 "$SYSTEM/${file}"
				chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
			done

			for dir in $sys_dir_list; do
				chmod 0755 "$SYSTEM/${dir}"
			done

			#ui_print "- Instalando mods en system_ext..."
			sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
			sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $sys_ext_list; do
				install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
				chmod 0644 "$SYSTEM_EXT/${file}"
				chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
			done

			for dir in $sys_ext_dir_list; do
				chmod 0755 "$SYSTEM_EXT/${dir}"
			done

			#ui_print "- Instalando mods en product..."
			pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
			pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

			for file in $pr_list; do
				install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
				chmod 0644 "$PRODUCT/${file}"
				chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
			done

			for dir in $pr_dir_list; do
				chmod 0755 "$PRODUCT/${dir}"
			done
			sleep 2.0
		else
			rm -rf $CORE_DIR/SDKPL13.tar.xz
		fi

	fi
	rm -rf $CORE_DIR
	rm -rf $REMOVER_FOLDER
}
gboard() {
	mkdir $TMP/remover
	chmod 0755 $TMP/remover
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP
	ui_print "* - Instalando Gboard lite...                    *"
	rm -rf $SYSTEM/app/LatinIMEGooglePrebuilt
	rm -rf $PRODUCT/priv-app/LatinIME
	rm -rf $PRODUCT/app/LatinIME
	rm -rf $PRODUCT/app/LatinIME
	rm -rf $PRODUCT/app/LatinIMEGooglePrebuilt
	rm -rf $PRODUCT/app/GBoard
	rm -rf $SYSTEM/lib64/libjni_latinimegoogle.so
	rm -rf $PRODUCT/app/LatinImeGoogle
	tar -xf "$CORE_DIR/SDKG.tar.xz" -C $REMOVER_FOLDER
	sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_list; do
		install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
		chmod 0644 "$SYSTEM/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
	done

	for dir in $sys_dir_list; do
		chmod 0755 "$SYSTEM/${dir}"
	done

	#ui_print "- Instalando mods en system_ext..."
	sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_ext_list; do
		install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
		chmod 0644 "$SYSTEM_EXT/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
	done

	for dir in $sys_ext_dir_list; do
		chmod 0755 "$SYSTEM_EXT/${dir}"
	done

	#ui_print "- Instalando mods en product..."
	pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
	pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $pr_list; do
		install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
		chmod 0644 "$PRODUCT/${file}"
		chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
	done

	for dir in $pr_dir_list; do
		chmod 0755 "$PRODUCT/${dir}"
	done
	rm -rf $CORE_DIR
	rm -rf $REMOVER_FOLDER
}
soundrice() {
	mkdir $TMP/remover
	chmod 0755 $TMP/remover
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP
	ui_print "* - Instalando Sonidos RICE...                   *"
	if [ -e $SYSTEM/media/audio ]; then
		mkdir $REMOVER_FOLDER/system
		REMOVER_SYS="$REMOVER_FOLDER/system"
		tar -xf "$CORE_DIR/SDKS.tar.xz" -C $REMOVER_SYS
	else
		mkdir $REMOVER_FOLDER/product
		REMOVER_PR="$REMOVER_FOLDER/product"
		tar -xf "$CORE_DIR/SDKS.tar.xz" -C $REMOVER_PR
	fi
	sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_list; do
		install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
		chmod 0644 "$SYSTEM/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
	done

	for dir in $sys_dir_list; do
		chmod 0755 "$SYSTEM/${dir}"
	done

	#ui_print "- Instalando mods en system_ext..."
	sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $sys_ext_list; do
		install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
		chmod 0644 "$SYSTEM_EXT/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
	done

	for dir in $sys_ext_dir_list; do
		chmod 0755 "$SYSTEM_EXT/${dir}"
	done

	#ui_print "- Instalando mods en product..."
	pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
	pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

	for file in $pr_list; do
		install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
		chmod 0644 "$PRODUCT/${file}"
		chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
	done

	for dir in $pr_dir_list; do
		chmod 0755 "$PRODUCT/${dir}"
	done
	rm -rf $CORE_DIR
	rm -rf $REMOVER_FOLDER
	sleep 2.0
}
desmontar_sistema() {
	ui_print "* - Borrando archivos temporales...              *"
	ui_print "*                                                *"
	ui_print "*               DESMONTANDO SYSTEM               *"
	sleep 2.0
	ui_print "*                                                *"
	if umount -l /system; then
		ui_print "* - Desmontado /system                           *"
	else
		ui_print "* x No desmontado /system                        *"
	fi

	if umount -l /system_root; then
		ui_print "* - Desmontado /system_root                      *"
	else
		ui_print "* x No desmontado /system_root                   *"
	fi

	if [ "$PRODUCT" = /product ]; then
		if umount -l /product; then
			ui_print "* - Desmontado /product                          *"
		else
			ui_print "* x No desmontado /product                       *"
		fi
	fi

	if [ "$VENDOR" = /vendor ]; then
		if umount -l /vendor; then
			ui_print "* - Desmontado /vendor                           *"
		else
			ui_print "* x No desmontado /vendor                        *"
		fi
	fi

	if [ "$SYSTEM_EXT" = /system_ext ]; then
		if umount -l /system_ext; then
			ui_print "* - Desmontado /system_ext                       *"
		else
			ui_print "* x No desmontado /system_ext                    *"
		fi
	fi

	[ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
	[ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
	[ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG
	ui_print "*                                                *"
	ui_print "*                   REALIZADO                    *"
	ui_print "*                                                *"
	ui_print "**************************************************"
	ui_print " "
}
creando_tmp
montando_sistema
android_version
debloater
photo
herramientas
pre_swizard
files
swizard
pl
if [ -e $SYSTEM_ROOT/my_stock ]; then
	desmontar_sistema
else
	gboard
	desmontar_sistema
fi
set_progress 1.00
