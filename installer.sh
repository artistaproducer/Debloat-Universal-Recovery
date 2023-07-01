#!/sbin/sh

# Función para imprimir mensajes en la interfaz de usuario
ui_print() {
	echo "ui_print $1" >"$OUTFD" # Imprime el mensaje en el descriptor de archivo "$OUTFD"
	echo "ui_print" >"$OUTFD"    # Imprime una línea vacía para separar mensajes en la interfaz
}

# Función para establecer el progreso en la interfaz de usuario
set_progress() {
	echo "set_progress $1" >"$OUTFD" # Establece el valor de progreso en el descriptor de archivo "$OUTFD"
}

# Función para configurar directorios temporales y de eliminación
creando_tmp() {
	TMP="/tmp"                                   # Directorio temporal principal
	CORE_DIR="$TMP/SDK"                          # Directorio para el núcleo del sistema
	REMOVER_FOLDER="$TMP/remover"                # Directorio para archivos a eliminar
	REMOVER_SYS="$REMOVER_FOLDER/system"         # Directorio para archivos del sistema a eliminar
	REMOVER_SYS_EXT="$REMOVER_FOLDER/system_ext" # Directorio para archivos de system_ext a eliminar
	REMOVER_PR="$REMOVER_FOLDER/product"         # Directorio para archivos de product a eliminar

	set_progress 0.10 # Establece el progreso al 10%
}

# Función para desmontar y volver a montar particiones del sistema
montando_sistema() {
	umount -l /system      # Desmonta la partición /system
	umount -l /system_root # Desmonta la partición /system_root
	umount -l /system_ext  # Desmonta la partición /system_ext
	umount -l /product     # Desmonta la partición /product
	umount -l /vendor      # Desmonta la partición /vendor

	system_as_root=$(getprop ro.build.system_root_image) # Verifica si el sistema está en modo "system-as-root"
	active_slot=$(getprop ro.boot.slot_suffix)           # Obtiene el slot activo (si existe)
	dynamic=$(getprop ro.boot.dynamic_partitions)        # Verifica si las particiones son dinámicas

	ui_print "*                                                *"
	ui_print "*              MONTANDO PARTICIONES              *"
	sleep 0.2
	ui_print "*                                                *"

	# Si las particiones son dinámicas
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
		# Si las particiones no son dinámicas
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

	$TMP/e2fsck -fy $system_block # Realiza la comprobación del sistema de archivos y corrige errores si los hay
	$TMP/resize2fs $system_block  # Redimensiona el sistema de archivos al tamaño actualizado
	sleep 0.2
	if [ ! -z "$product_block" ]; then
		$TMP/e2fsck -fy $product_block # Realiza la comprobación del sistema de archivos de product y corrige errores si los hay
		$TMP/resize2fs $product_block  # Redimensiona el sistema de archivos de product al tamaño actualizado
		sleep 0.2
	fi

	# Si las particiones son dinámicas
	if [ "$dynamic" = "true" ]; then
		$TMP/e2fsck -fy $system_ext_block # Realiza la comprobación del sistema de archivos de system_ext y corrige errores si los hay
		$TMP/resize2fs $system_ext_block  # Redimensiona el sistema de archivos de system_ext al tamaño actualizado
	fi

	##### DETECT & MOUNT SYSTEM #####
	sleep 0.2
	mount_system() {
		mkdir -p /system      # Crea el directorio /system
		mkdir -p /system_root # Crea el directorio /system_root

		# Intenta montar la partición /system o /system_root (dependiendo de la configuración del sistema)
		if mount -o rw $system_block /system_root; then
			if [ -e /system_root/build.prop ]; then
				MOUNTED=/system_root
				ui_print "* - SYSTEM Detectado!                            *"
			else
				MOUNTED=/system_root/system
				ui_print "* - SYSTEM_ROOT Detectado!                       *"
			fi
			mount -o bind $MOUNTED /system # Enlaza el sistema montado al directorio /system
			SYSTEM=/system                 # Establece la variable SYSTEM al directorio /system
			ui_print "* - SYSTEM Enlazado!                             *"
		else
			ui_print "* - No se pudo montar SYSTEM!                    *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
			umount -l /system && umount -l /system_root # Desmonta las particiones en caso de error y finaliza el script
			exit 1
		fi
	}

	mount_system # Llama a la función para montar la partición del sistema
	sleep 0.2

	##### DETECT & MOUNT PRODUCT #####

	mkdir -p /product # Crea el directorio /product

	# Verifica si existen archivos de product en la partición del sistema o se monta la partición de product
	if [ -e $SYSTEM/product/build.prop ] || [ -e $SYSTEM/product/etc/build.prop ] || [ -e $SYSTEM/phh ]; then
		ui_print "| Using /system/product"
		PRODUCT=/system/product
	else
		if mount -o rw $product_block /product; then
			ui_print "* - PRODUCT Enlazado!                            *"
			PRODUCT=/product # Establece la variable PRODUCT al directorio /product
		else
			ui_print "* - No se pudo montar PRODUCT!                   *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
		fi
	fi

	##### DETECT & MOUNT SYSTEM_EXT #####

	mkdir -p /system_ext # Crea el directorio /system_ext

	# Verifica si existen archivos de system_ext en la partición del sistema o se monta la partición de system_ext
	if [ -e $SYSTEM/system_ext/build.prop ] || [ -e $SYSTEM/system_ext/etc/build.prop ] || [ -e $SYSTEM/phh ]; then
		SYSTEM_EXT=/system/system_ext # Establece la variable SYSTEM_EXT al directorio /system/system_ext
	else
		if mount -o rw $system_ext_block /system_ext; then
			ui_print "* - SYSTEM_EXT Enlazado!                         *"
			SYSTEM_EXT=/system_ext # Establece la variable SYSTEM_EXT al directorio /system_ext
		else
			ui_print "* - No se pudo montar SYSTEM_EXT!                *"
			ui_print "* - Pruebe el fix de error 1 si esta en miui     *"
			ui_print "*   o el Debloat modulo para Magisk!             *"
			ui_print "**************************************************"
		fi
	fi

	mkdir -p /vendor # Crea el directorio /vendor

	if mount -o rw $vendor_block /vendor; then
		ui_print "* - VENDOR Enlazado!                             *"
		VENDOR=/vendor # Establece la variable VENDOR al directorio /vendor
	fi

	sleep 0.2
	set_progress 0.20 # Establece el progreso al 20%

	OLD_LD_LIB=$LD_LIBRARY_PATH
	OLD_LD_PRE=$LD_PRELOAD
	OLD_LD_CFG=$LD_CONFIG_FILE
	unset LD_LIBRARY_PATH
	unset LD_PRELOAD
	unset LD_CONFIG_FILE
}# Función para identificar la versión de Android
android_version() {
	ui_print "*                                                *"
	ui_print "*        IDENTIFICANDO VERSION DE ANDROID        *"
	sleep 0.2
	ui_print "*                                                *"
	android_sdk=$(cat /system/build.prop | grep -o 'ro.system.build.version.sdk[^ ]*' | cut -c 29-30)
	
	# Identificar la versión de Android según el SDK
	if [ "$android_sdk" = 29 ]; then
		ui_print "* - Android 10                                   *"
		ui_print "* - SDK: 29                                      *"
	fi
	if [ "$android_sdk" = 30 ]; then
		ui_print "* - Android 11                                   *"
		ui_print "* - SDK: 30                                      *"
	fi
	if [ "$android_sdk" = 31 ]; then
		ui_print "* - Android 12                                   *"
		ui_print "* - SDK: 31                                      *"
	fi
	if [ "$android_sdk" = 32 ]; then
		ui_print "* - Android 12L                                  *"
		ui_print "* - SDK: 32                                      *"
	fi
	if [ "$android_sdk" = 33 ]; then
		ui_print "* - Android 13                                   *"
		ui_print "* - SDK: 33                                      *"
	fi
}

##limpiando rom
debloater() {
	ui_print "*                                                *"
	ui_print "*                  LIMPIANDO ROM                 *"
	sleep 0.5
	ui_print "*                                                *"
	#esta lista es para apps de miui, más abajo encuentra la lista para aosp

	if [ -e $SYSTEM/app/miuisystem ] || [ -e $SYSTEM_EXT/app/miuisystem ] || [ -e $SYSTEM_EXT/priv-app/MiuiSystemUIPlugin ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ] || [ -e $SYSTEM/app/miui ]; then
		ui_print "* - Borrando apps en MIUI...                     *"
		if [ -e /data/data/com.miui.core ]; then
			rm -rf $PRODUCT/*pp/PixelSetupWizard
			rm -rf $PRODUCT/*pp/SetupWizard
			rm -rf $PRODUCT/*pp/SetupWizardPrebuilt
			rm -rf $SYSTEM/*pp/SetupWizard
			rm -rf $SYSTEM_EXT/*pp/PixelSetupWizard
			rm -rf $SYSTEM_EXT/*pp/SetupWizard
		fi
		rm -rf $PRODUCT/*pp/MIUISuperMarket
		rm -rf $SYSTEM/*pp/AbleMusic
		rm -rf $SYSTEM/*pp/AiAsstVision
		rm -rf $SYSTEM/*pp/AnalyticsCore
		rm -rf $SYSTEM/*pp/AndroidAutoStub
		rm -rf $SYSTEM/*pp/AntHalService
		rm -rf $SYSTEM/*pp/Backup
		rm -rf $SYSTEM/*pp/BasicDreams
		rm -rf $SYSTEM/*pp/BookmarkProvider
		rm -rf $SYSTEM/*pp/Browser
		rm -rf $SYSTEM/*pp/BugReport
		rm -rf $SYSTEM/*pp/CalculatorGlobalStub
		rm -rf $SYSTEM/*pp/CatchLog
		rm -rf $SYSTEM/*pp/Cit
		rm -rf $SYSTEM/*pp/Compass
		rm -rf $SYSTEM/*pp/CompassGlobalStub
		rm -rf $SYSTEM/*pp/CovenantBR
		rm -rf $SYSTEM/*pp/Email
		rm -rf $SYSTEM/*pp/EmergencyInfo
		rm -rf $SYSTEM/*pp/FM_QCOM
		rm -rf $SYSTEM/*pp/FrequentPhrase
		rm -rf $SYSTEM/*pp/GoogleAssistant
		rm -rf $SYSTEM/*pp/GoogleFeedback
		rm -rf $SYSTEM/*pp/GoogleOneTimeInitializer
		rm -rf $SYSTEM/*pp/GoogleRestore
		rm -rf $SYSTEM/*pp/Health
		rm -rf $SYSTEM/*pp/HybridAccessory
		rm -rf $SYSTEM/*pp/HybridPlatform
		rm -rf $SYSTEM/*pp/IdMipay
		rm -rf $SYSTEM/*pp/InMipay
		rm -rf $SYSTEM/*pp/KSICibaEngine
		rm -rf $SYSTEM/*pp/Lens
		rm -rf $SYSTEM/*pp/LiveWallpapersPicker
		rm -rf $SYSTEM/*pp/MIDrop
		rm -rf $SYSTEM/*pp/MINextPay
		rm -rf $SYSTEM/*pp/MIRadioGlobalBuiltin
		rm -rf $SYSTEM/*pp/MIUICompassGlobal
		rm -rf $SYSTEM/*pp/MIUINotes
		rm -rf $SYSTEM/*pp/MIUISecurityInputMethod
		rm -rf $SYSTEM/*pp/MIUIVideoPlaye
		rm -rf $SYSTEM/*pp/MIUIVideoPlayer
		rm -rf $SYSTEM/*pp/MIpay
		rm -rf $SYSTEM/*pp/MSA
		rm -rf $SYSTEM/*pp/MSA-Global
		rm -rf $SYSTEM/*pp/MiBrowserGlobal
		rm -rf $SYSTEM/*pp/MiBugReport
		rm -rf $SYSTEM/*pp/MiCloudSync
		rm -rf $SYSTEM/*pp/MiConnectService171
		rm -rf $SYSTEM/*pp/MiDrive
		rm -rf $SYSTEM/*pp/MiDrop
		rm -rf $SYSTEM/*pp/MiDropStub
		rm -rf $SYSTEM/*pp/MiFitness
		rm -rf $SYSTEM/*pp/MiGalleryLockscreen
		rm -rf $SYSTEM/*pp/MiMoverGlobal
		rm -rf $SYSTEM/*pp/MiPicks
		rm -rf $SYSTEM/*pp/MiPlayClient
		rm -rf $SYSTEM/*pp/MiRadio
		rm -rf $SYSTEM/*pp/Mipay
		rm -rf $SYSTEM/*pp/MiuiAccessibility
		rm -rf $SYSTEM/*pp/MiuiBrowserGlobal
		rm -rf $SYSTEM/*pp/MiuiBugReport
		rm -rf $SYSTEM/*pp/MiuiCompass
		rm -rf $SYSTEM/*pp/MiuiDaemon
		rm -rf $SYSTEM/*pp/MiuiFrequentPhrase
		rm -rf $SYSTEM/*pp/MiuiGalleryLockscreen
		rm -rf $SYSTEM/*pp/Netflix_activation
		rm -rf $SYSTEM/*pp/NextPay
		rm -rf $SYSTEM/*pp/Notes
		rm -rf $SYSTEM/*pp/NotesGlobalStub
		rm -rf $SYSTEM/*pp/OneTimeInitializer
		rm -rf $SYSTEM/*pp/OsuLogin
		rm -rf $SYSTEM/*pp/PartnerBookmarksProvider
		rm -rf $SYSTEM/*pp/PaymentService
		rm -rf $SYSTEM/*pp/PersonalAssistant
		rm -rf $SYSTEM/*pp/PersonalAssistantGlobal
		rm -rf $SYSTEM/*pp/PlayAutoInstallStubApp
		rm -rf $SYSTEM/*pp/SolidExplorer
		rm -rf $SYSTEM/*pp/SolidExplorerUnlocker
		rm -rf $SYSTEM/*pp/TSMClient
		rm -rf $SYSTEM/*pp/TouchAssistant
		rm -rf $SYSTEM/*pp/Traceur
		rm -rf $SYSTEM/*pp/TranslationService
		rm -rf $SYSTEM/*pp/Turbo
		rm -rf $SYSTEM/*pp/UPTsmService
		rm -rf $SYSTEM/*pp/Velvet
		rm -rf $SYSTEM/*pp/VideoPlayer
		rm -rf $SYSTEM/*pp/Videos
		rm -rf $SYSTEM/*pp/VoiceAssist
		rm -rf $SYSTEM/*pp/VoiceAssistant
		rm -rf $SYSTEM/*pp/VoiceTrigger
		rm -rf $SYSTEM/*pp/VsimCore
		rm -rf $SYSTEM/*pp/WAPPushManager
		rm -rf $SYSTEM/*pp/WMServices
		rm -rf $SYSTEM/*pp/WellbeingPrebuilt
		rm -rf $SYSTEM/*pp/XMCloudEngine
		rm -rf $SYSTEM/*pp/XMSFKeeper
		rm -rf $SYSTEM/*pp/XPeriaWeather
		rm -rf $SYSTEM/*pp/XiaomiSimActivateService
		rm -rf $SYSTEM/*pp/YTProMicrog
		rm -rf $SYSTEM/*pp/YouDaoEngine
		rm -rf $SYSTEM/*pp/YouTube
		rm -rf $SYSTEM/*pp/YoutubeVanced
		rm -rf $SYSTEM/*pp/Yunikon
		rm -rf $SYSTEM/*pp/arcore
		rm -rf $SYSTEM/*pp/com.xiaomi.macro
		rm -rf $SYSTEM/*pp/facebook
		rm -rf $SYSTEM/*pp/facebook-appmanager
		rm -rf $SYSTEM/*pp/greenguard
		rm -rf $SYSTEM/*pp/mab
		rm -rf $SYSTEM/*pp/mi_connect_service
		rm -rf $SYSTEM/*pp/wps-lite
		rm -rf $SYSTEM/*pp/wps_lite
		rm -rf $SYSTEM/*pp/Gmail2
		rm -rf $SYSTEM/*pp/MIBrowserGlobal
		rm -rf $SYSTEM/*pp/MIGalleryLockScreen
		rm -rf $SYSTEM/*pp/MIGalleryLockScreenGlobal
		rm -rf $SYSTEM/*pp/MIGalleryLockscreen
		rm -rf $SYSTEM/*pp/MIGalleryLockscreenGlobal
		rm -rf $SYSTEM/*pp/MIMediaEditorGlobal
		rm -rf $SYSTEM/*pp/MIUICompass
		rm -rf $SYSTEM/*pp/MIUICompassGlobal
		rm -rf $SYSTEM/*pp/MIUISuperMarket
		rm -rf $SYSTEM/*pp/MiCreditInStub
		rm -rf $SYSTEM/*pp/MiRemote
		rm -rf $SYSTEM/*pp/ShareMe
		rm -rf $SYSTEM/*pp/XMRemoteController
		rm -rf $SYSTEM/*pp/yellowpage
		rm -rf $SYSTEM/*pp/AndroidAutoStub
		rm -rf $SYSTEM/*pp/AntHalService
		rm -rf $SYSTEM/*pp/Backup
		rm -rf $SYSTEM/*pp/BasicDreams
		rm -rf $SYSTEM/*pp/BookmarkProvider
		rm -rf $SYSTEM/*pp/Browser
		rm -rf $SYSTEM/*pp/BugReport
		rm -rf $SYSTEM/*pp/CatchLog
		rm -rf $SYSTEM/*pp/CellBroadcastServiceModulePlatform
		rm -rf $SYSTEM/*pp/Cit
		rm -rf $SYSTEM/*pp/CloudBackup
		rm -rf $SYSTEM/*pp/CloudService
		rm -rf $SYSTEM/*pp/CloudServiceSysbase
		rm -rf $SYSTEM/*pp/EmergencyInfo
		rm -rf $SYSTEM/*pp/GameCenterGlobal
		rm -rf $SYSTEM/*pp/GlobalMinusScreen
		rm -rf $SYSTEM/*pp/GoogleAssistant
		rm -rf $SYSTEM/*pp/GoogleFeedback
		rm -rf $SYSTEM/*pp/GoogleOneTimeInitializer
		rm -rf $SYSTEM/*pp/GoogleRestore
		rm -rf $SYSTEM/*pp/GoogleTTS
		rm -rf $SYSTEM/*pp/HotwordEnrollmentOKGoogleWCD9340
		rm -rf $SYSTEM/*pp/HotwordEnrollmentXGoogleWCD9340
		rm -rf $SYSTEM/*pp/MIService
		rm -rf $SYSTEM/*pp/MIShare
		rm -rf $SYSTEM/*pp/MIShareGlobal
		rm -rf $SYSTEM/*pp/MIUIYellowPage
		rm -rf $SYSTEM/*pp/MIUIYellowPageGlobal
		rm -rf $SYSTEM/*pp/MiBrowser
		rm -rf $SYSTEM/*pp/MiBrowserGlobal
		rm -rf $SYSTEM/*pp/MiCloudSync
		rm -rf $SYSTEM/*pp/MiDrive
		rm -rf $SYSTEM/*pp/MiDrop
		rm -rf $SYSTEM/*pp/MiGame
		rm -rf $SYSTEM/*pp/MiGameCenterSDKService
		rm -rf $SYSTEM/*pp/MiMover
		rm -rf $SYSTEM/*pp/MiMoverGlobal
		rm -rf $SYSTEM/*pp/MiPlayClient
		rm -rf $SYSTEM/*pp/MiService
		rm -rf $SYSTEM/*pp/MiShare
		rm -rf $SYSTEM/*pp/MiuiBrowser
		rm -rf $SYSTEM/*pp/MiuiBrowserGlobal
		rm -rf $SYSTEM/*pp/MiuiBugReport
		rm -rf $SYSTEM/*pp/Notes
		rm -rf $SYSTEM/*pp/ONS
		rm -rf $SYSTEM/*pp/OneTimeInitializer
		rm -rf $SYSTEM/*pp/PartnerBookmarksProvider
		rm -rf $SYSTEM/*pp/PersonalAssistant
		rm -rf $SYSTEM/*pp/PersonalAssistantGlobal
		rm -rf $SYSTEM/*pp/QuickSearchBox
		rm -rf $SYSTEM/*pp/Velvet
		rm -rf $SYSTEM/*pp/Videos
		rm -rf $SYSTEM/*pp/VoiceCommand
		rm -rf $SYSTEM/*pp/VoiceTrigger
		rm -rf $SYSTEM/*pp/VoiceUnlock
		rm -rf $SYSTEM/*pp/WellbeingPreBuilt
		rm -rf $SYSTEM/*pp/WellbeingPrebuilt
		rm -rf $SYSTEM/*pp/YellowPage
		rm -rf $SYSTEM/*pp/YouTube
		rm -rf $SYSTEM/*pp/arcore
		rm -rf $SYSTEM/*pp/facebook
		rm -rf $SYSTEM/*pp/facebook-installer
		rm -rf $SYSTEM/*pp/facebook-services
		rm -rf $PRODUCT/*pp/AiAsstVision
		rm -rf $PRODUCT/*pp/AiasstVision_L2
		rm -rf $PRODUCT/*pp/AndroidAutoStub
		rm -rf $PRODUCT/*pp/Backup
		rm -rf $PRODUCT/*pp/CalendarGoogle
		rm -rf $PRODUCT/*pp/CarWith
		rm -rf $PRODUCT/*pp/Chrome
		rm -rf $PRODUCT/*pp/Chrome-Stub
		rm -rf $PRODUCT/*pp/Chrome64
		rm -rf $PRODUCT/*pp/Cit
		rm -rf $PRODUCT/*pp/CloudBackup
		rm -rf $PRODUCT/*pp/CloudService
		rm -rf $PRODUCT/*pp/Compass
		rm -rf $PRODUCT/*pp/DevicePolicyPrebuilt
		rm -rf $PRODUCT/*pp/Email
		rm -rf $PRODUCT/*pp/EmergencyInfo
		rm -rf $PRODUCT/*pp/FM
		rm -rf $PRODUCT/*pp/GameCenterGlobal
		rm -rf $PRODUCT/*pp/GlobalFashiongallery
		rm -rf $PRODUCT/*pp/Gmail2
		rm -rf $PRODUCT/*pp/GoogleAssistant
		rm -rf $PRODUCT/*pp/GoogleFeedback
		rm -rf $PRODUCT/*pp/GoogleOne
		rm -rf $PRODUCT/*pp/GoogleOneTimeInitializer
		rm -rf $PRODUCT/*pp/GooglePay
		rm -rf $PRODUCT/*pp/GoogleRestore
		rm -rf $PRODUCT/*pp/GoogleTTS
		rm -rf $PRODUCT/*pp/Health
		rm -rf $PRODUCT/*pp/MIDrop
		rm -rf $PRODUCT/*pp/MINextpay
		rm -rf $PRODUCT/*pp/MIRadio
		rm -rf $PRODUCT/*pp/MIRadioGlobal
		rm -rf $PRODUCT/*pp/MITSMClient
		rm -rf $PRODUCT/*pp/MIUIAiasstService
		rm -rf $PRODUCT/*pp/MIUICloudService
		rm -rf $PRODUCT/*pp/MIUICloudServiceGlobal
		rm -rf $PRODUCT/*pp/MIUICompass
		rm -rf $PRODUCT/*pp/MIUICompassGlobal
		rm -rf $PRODUCT/*pp/MIUIMiCloudSync
		rm -rf $PRODUCT/*pp/MIUIMiPicks
		rm -rf $PRODUCT/*pp/MIUINotes
		rm -rf $PRODUCT/*pp/MIUIReporter
		rm -rf $PRODUCT/*pp/MIUISecurityInputMethod
		rm -rf $PRODUCT/*pp/MIUISuperMarket
		rm -rf $PRODUCT/*pp/MIUIVideoPlayer
		rm -rf $PRODUCT/*pp/MIpay
		rm -rf $PRODUCT/*pp/Maps
		rm -rf $PRODUCT/*pp/MiBugReport
		rm -rf $PRODUCT/*pp/MiCloudSync
		rm -rf $PRODUCT/*pp/MiConnectService
		rm -rf $PRODUCT/*pp/MiDrive
		rm -rf $PRODUCT/*pp/MiGalleryLockScreenGlobalT
		rm -rf $PRODUCT/*pp/MiGalleryLockscreen
		rm -rf $PRODUCT/*pp/MiMediaEditor
		rm -rf $PRODUCT/*pp/MIMediaEditor
		rm -rf $PRODUCT/*pp/MiRadio
		rm -rf $PRODUCT/*pp/MiuiBugReport
		rm -rf $PRODUCT/*pp/MiuiBugReportGlobal
		rm -rf $PRODUCT/*pp/MiuiCit
		rm -rf $PRODUCT/*pp/MiuiCompass
		rm -rf $PRODUCT/*pp/MiuiReporter
		rm -rf $PRODUCT/*pp/MiuiVideoGlobal
		rm -rf $PRODUCT/*pp/Notes
		rm -rf $PRODUCT/*pp/OmniJaws
		rm -rf $PRODUCT/*pp/PaymentService
		rm -rf $PRODUCT/*pp/PaymentService_Global
		rm -rf $PRODUCT/*pp/Photos
		rm -rf $PRODUCT/*pp/PrebuiltGmail
		rm -rf $PRODUCT/*pp/Reporter
		rm -rf $PRODUCT/*pp/SimActivateService
		rm -rf $PRODUCT/*pp/SimActivateServiceGlobal
		rm -rf $PRODUCT/*pp/SogouInput
		rm -rf $PRODUCT/*pp/SpeechServicesByGoogle
		rm -rf $PRODUCT/*pp/Velvet
		rm -rf $PRODUCT/*pp/VideoPlayer
		rm -rf $PRODUCT/*pp/VoiceAssist
		rm -rf $PRODUCT/*pp/VoiceAssistAndroidT
		rm -rf $PRODUCT/*pp/VoiceTrigger
		rm -rf $PRODUCT/*pp/WellbeingPrebuilt
		rm -rf $PRODUCT/*pp/XPerienceWallpapers
		rm -rf $PRODUCT/*pp/XiaoaiRecommendation
		rm -rf $PRODUCT/*pp/XiaomiServiceFramework
		rm -rf $PRODUCT/*pp/XiaomiSimActivateService
		rm -rf $PRODUCT/*pp/YMusic
		rm -rf $PRODUCT/*pp/YouTube
		rm -rf $PRODUCT/*pp/aiasst_service
		rm -rf $PRODUCT/*pp/arcore
		rm -rf $PRODUCT/*pp/mi_connect_service
		rm -rf $PRODUCT/*pp/mi_connect_service_t
		rm -rf $PRODUCT/*pp/wps-lite
		rm -rf $PRODUCT/*pp/BaiduIME
		rm -rf $PRODUCT/*pp/Drive
		rm -rf $PRODUCT/*pp/Duo
		rm -rf $PRODUCT/*pp/GlobalWPSLITE
		rm -rf $PRODUCT/*pp/GoogleNews
		rm -rf $PRODUCT/*pp/Health
		rm -rf $PRODUCT/*pp/MIGalleryLockscreen-T
		rm -rf $PRODUCT/*pp/MIMediaEditorGlobal
		rm -rf $PRODUCT/*pp/MIService
		rm -rf $PRODUCT/*pp/MIUICompass
		rm -rf $PRODUCT/*pp/MIUIDuokanReader
		rm -rf $PRODUCT/*pp/MIUIEmail
		rm -rf $PRODUCT/*pp/MIUIHuanji
		rm -rf $PRODUCT/*pp/MIUIMiDrive
		rm -rf $PRODUCT/*pp/MIUINotes
		rm -rf $PRODUCT/*pp/MIUIVipAccount
		rm -rf $PRODUCT/*pp/MIUIVirtualSim
		rm -rf $PRODUCT/*pp/MIUIXiaoAiSpeechEngine
		rm -rf $PRODUCT/*pp/MIUIYoupin
		rm -rf $PRODUCT/*pp/MiGalleryLockScreenGlobalT
		rm -rf $PRODUCT/*pp/MiMediaEditor
		rm -rf $PRODUCT/*pp/MiShop
		rm -rf $PRODUCT/*pp/POCOCOMMUNITY_OVERSEA
		rm -rf $PRODUCT/*pp/POCOSTORE_OVERSEA
		rm -rf $PRODUCT/*pp/Photos
		rm -rf $PRODUCT/*pp/Podcasts
		rm -rf $PRODUCT/*pp/ThirdAppAssistant
		rm -rf $PRODUCT/*pp/Videos
		rm -rf $PRODUCT/*pp/XMRemoteController
		rm -rf $PRODUCT/*pp/YTMusic
		rm -rf $PRODUCT/*pp/com.iflytek.inputmethod.miui
		rm -rf $PRODUCT/*pp/wps-lite
		rm -rf $PRODUCT/*pp/AndroidAutoStub
		rm -rf $PRODUCT/*pp/Backup
		rm -rf $PRODUCT/*pp/Chrome
		rm -rf $PRODUCT/*pp/CloudBackup
		rm -rf $PRODUCT/*pp/EmergencyInfo
		rm -rf $PRODUCT/*pp/GoogleAssistant
		rm -rf $PRODUCT/*pp/GoogleFeedback
		rm -rf $PRODUCT/*pp/GoogleOneTimeInitializer
		rm -rf $PRODUCT/*pp/GoogleRestore
		rm -rf $PRODUCT/*pp/GoogleRestorePrebuilt
		rm -rf $PRODUCT/*pp/HelpRtcPrebuilt
		rm -rf $PRODUCT/*pp/HotwordEnrollmentOKGoogleHEXAGON_WIDEBAND
		rm -rf $PRODUCT/*pp/HotwordEnrollmentXGoogleHEXAGON_WIDEBAND
		rm -rf $PRODUCT/*pp/MIService
		rm -rf $PRODUCT/*pp/MIServiceGlobal
		rm -rf $PRODUCT/*pp/MIShare
		rm -rf $PRODUCT/*pp/MIShareGlobal
		rm -rf $PRODUCT/*pp/MIUIBrowser
		rm -rf $PRODUCT/*pp/MIUICloudBackup
		rm -rf $PRODUCT/*pp/MIUICloudBackupGlobal
		rm -rf $PRODUCT/*pp/MIUIQuickSearchBox
		rm -rf $PRODUCT/*pp/MIUIVideo
		rm -rf $PRODUCT/*pp/MIUIYellowPage
		rm -rf $PRODUCT/*pp/MIUIYellowPageGlobal
		rm -rf $PRODUCT/*pp/MiBrowserGlobal
		rm -rf $PRODUCT/*pp/MiMover
		rm -rf $PRODUCT/*pp/MiService
		rm -rf $PRODUCT/*pp/MiShare
		rm -rf $PRODUCT/*pp/Mirror
		rm -rf $PRODUCT/*pp/MiuiVideo
		rm -rf $PRODUCT/*pp/Notes
		rm -rf $PRODUCT/*pp/NovaBugreportWrapper
		rm -rf $PRODUCT/*pp/PersonalAssistant
		rm -rf $PRODUCT/*pp/PersonalSafety
		rm -rf $PRODUCT/*pp/Velvet
		rm -rf $PRODUCT/*pp/Wellbeing
		rm -rf $PRODUCT/*pp/WellbeingPreBuilt
		rm -rf $PRODUCT/*pp/WellbeingPrebuilt
		rm -rf $PRODUCT/*pp/YouTube
		rm -rf $PRODUCT/*pp/arcore
		rm -rf $SYSTEM_EXT/*pp/FM
		rm -rf $SYSTEM_EXT/*pp/FM_Test
		rm -rf $SYSTEM_EXT/*pp/Papers
		rm -rf $SYSTEM_EXT/*pp/EmergencyInfo
		rm -rf $SYSTEM_EXT/*pp/EmergencyInfoGms
		rm -rf $SYSTEM_EXT/*pp/FMRadio
		rm -rf $SYSTEM_EXT/*pp/GoogleFeedback
		rm -rf $SYSTEM_EXT/*pp/Leaflet
		rm -rf $SYSTEM_EXT/*pp/MatLogrm#
		rm -rf $SYSTEM/vendor/*pp/SoterService
		rm -rf $SYSTEM/vendor/*pp/Drive
		rm -rf $SYSTEM/vendor/*pp/Duo
		rm -rf $SYSTEM/vendor/*pp/Music2
		rm -rf $SYSTEM/vendor/*pp/Photos
		rm -rf $SYSTEM/vendor/*pp/SoterService
		rm -rf $SYSTEM/vendor/*pp/XMRemoteController
		#
		#
		#
		#debloat  para AOSP
		#
		#
		#
		sleep 0.5
	elif [ -e /system_root/my_stock ]; then #debloat para oxigen
		SYSTEM_ROOT="/system_root"
		ui_print "* - Borrando apps en OxigenOS...                 *"
		rm -rf $SYSTEM_ROOT/my*/*pp/AssistantScreen
		rm -rf $SYSTEM_ROOT/my*/*pp/OplusSecurityKeyboard
		rm -rf $SYSTEM_ROOT/my*/*pp/OPCommunity
		rm -rf $SYSTEM_ROOT/my*/*pp/DocumentReader
		rm -rf $SYSTEM_ROOT/my*/*pp/OppoNote2
		rm -rf $SYSTEM_EXT/*pp/LogKit
		rm -rf $SYSTEM_EXT/*pp/Olc
		rm -rf $SYSTEM_ROOT/my*/*pp/ARCore_stub
		rm -rf $SYSTEM_ROOT/my*/*pp/ARCore
		rm -rf $SYSTEM_ROOT/my*/*pp/Browser
		rm -rf $SYSTEM_ROOT/my*/*pp/ChildrenSpace
		rm -rf $SYSTEM_ROOT/my*/*pp/DigitalWellBeing
		rm -rf $SYSTEM_ROOT/my*/*pp/Health
		rm -rf $SYSTEM_ROOT/my*/*pp/BookmarkProvider
		rm -rf $SYSTEM_ROOT/my*/*pp/Chrome
		rm -rf $PRODUCT/*pp/Omoji
		rm -rf $PRODUCT/*pp/DigitalWellBeing
		rm -rf $PRODUCT/*pp/ARCore
		rm -rf $PRODUCT/*pp/Browser
		rm -rf $SYSTEM_EXT/*pp/SoterService
		rm -rf $SYSTEM_ROOT/my*/*pp/Gmail2
		rm -rf $SYSTEM_ROOT/my*/*pp/ChromePartnerProvider
		rm -rf $SYSTEM_ROOT/my*/*pp/Maps
		rm -rf $SYSTEM_ROOT/my*/*pp/YouTube
		rm -rf $SYSTEM_ROOT/my*/*pp/talkback
		rm -rf $SYSTEM_ROOT/my*/*pp/SoundAmplifier
		rm -rf $SYSTEM_ROOT/my*/*pp/Keep
		rm -rf $SYSTEM_ROOT/my*/*pp/WellbeingAssistant
		rm -rf $SYSTEM_ROOT/my*/*pp/ARCore
		rm -rf $SYSTEM_ROOT/my*/*pp/Chrome
		rm -rf $SYSTEM_ROOT/my*/*pp/Music
		rm -rf $SYSTEM_ROOT/my*/*pp/SpeechServicesByGoogle
		rm -rf $SYSTEM_ROOT/my*/*pp/talkback
		rm -rf $SYSTEM_ROOT/my*/non_overlay/*pp/SetupWizard
		rm -rf $SYSTEM_ROOT/my*/*pp/AndroidAutoStub
		rm -rf $SYSTEM_ROOT/my*/*pp/GoogleRestore
		rm -rf $SYSTEM_ROOT/my*/*pp/Velvet
		rm -rf $SYSTEM_ROOT/my*/*pp/Wellbeing
		rm -rf $SYSTEM_ROOT/my*/*pp/ChildrenSpace
		rm -rf $SYSTEM_ROOT/my*/*pp/OPlusSegurityKeyboard
		rm -rf $SYSTEM_ROOT/my*/*pp/OplusOperationManual
		rm -rf $SYSTEM_ROOT/my*/*pp/OPBreathMode
		rm -rf $SYSTEM_ROOT/my*/*pp/OPNote
		rm -rf $SYSTEM_ROOT/my*/*pp/KeKeUserCenter
		rm -rf $SYSTEM_ROOT/my*/*pp/SOSHelper
		rm -rf $SYSTEM_ROOT/my*/*pp/Omoji
		rm -rf $SYSTEM_ROOT/my*/*pp/HotwordEnrollment*
		sleep 0.5
	else
		ui_print "* - Borrando apps en AOSP...                     *"
		rm -rf $SYSTEM/*pp/AEXPapers
		rm -rf $SYSTEM/*pp/AbleMusic
		rm -rf $SYSTEM/*pp/Abstruct
		rm -rf $SYSTEM/*pp/Aves
		rm -rf $SYSTEM/*pp/BasicDreams
		rm -rf $SYSTEM/*pp/BlissPapers
		rm -rf $SYSTEM/*pp/BlissUpdater
		rm -rf $SYSTEM/*pp/BookmarkProvider
		rm -rf $SYSTEM/*pp/Browser
		rm -rf $SYSTEM/*pp/Bug2GoStub
		rm -rf $SYSTEM/*pp/Chromium
		rm -rf $SYSTEM/*pp/ColtPapers
		rm -rf $SYSTEM/*pp/DuckDuckGo
		rm -rf $SYSTEM/*pp/Duckduckgo
		rm -rf $SYSTEM/*pp/EggGame
		rm -rf $SYSTEM/*pp/Email
		rm -rf $SYSTEM/*pp/Exchange2
		rm -rf $SYSTEM/*pp/FM2
		rm -rf $SYSTEM/*pp/FMRadioService
		rm -rf $SYSTEM/*pp/Gallery
		rm -rf $SYSTEM/*pp/GugelClock
		rm -rf $SYSTEM/*pp/Jelly
		rm -rf $SYSTEM/*pp/Kiwi
		rm -rf $SYSTEM/*pp/MiXplorer
		rm -rf $SYSTEM/*pp/Music
		rm -rf $SYSTEM/*pp/MusicPlayerGO
		rm -rf $SYSTEM/*pp/Phonograph
		rm -rf $SYSTEM/*pp/PhotoTable
		rm -rf $SYSTEM/*pp/QPGallery
		rm -rf $SYSTEM/*pp/RetroMusic
		rm -rf $SYSTEM/*pp/RetroMusicPlayer
		rm -rf $SYSTEM/*pp/RetroMusicPlayerPrebuilt
		rm -rf $SYSTEM/*pp/SeedVault
		rm -rf $SYSTEM/*pp/SimpleCalendar
		rm -rf $SYSTEM/*pp/SimpleGallery
		rm -rf $SYSTEM/*pp/StagWalls
		rm -rf $SYSTEM/*pp/Superiorwalls
		rm -rf $SYSTEM/*pp/TilesWallpaper
		rm -rf $SYSTEM/*pp/VanillaMusic
		rm -rf $SYSTEM/*pp/Velvet
		rm -rf $SYSTEM/*pp/Via
		rm -rf $SYSTEM/*pp/ViaBrowser
		rm -rf $SYSTEM/*pp/WellbeingPrebuilt
		rm -rf $SYSTEM/*pp/YTMusic
		rm -rf $SYSTEM/*pp/YouTube
		rm -rf $SYSTEM/*pp/Yunikon
		rm -rf $SYSTEM/*pp/arcore
		rm -rf $SYSTEM/*pp/crDroidMusic
		rm -rf $SYSTEM/*pp/facebook-appmanager
		rm -rf $SYSTEM/*pp/AudioFX
		rm -rf $SYSTEM/*pp/BlissUpdater
		rm -rf $SYSTEM/*pp/Calendar
		rm -rf $SYSTEM/*pp/DigitalWellbeing
		rm -rf $SYSTEM/*pp/EasySetup
		rm -rf $SYSTEM/*pp/Eleven
		rm -rf $SYSTEM/*pp/Email
		rm -rf $SYSTEM/*pp/FM2
		rm -rf $SYSTEM/*pp/Gallery2
		rm -rf $SYSTEM/*pp/MatLog
		rm -rf $SYSTEM/*pp/MetroMusicPlayer
		rm -rf $SYSTEM/*pp/MusicFX
		rm -rf $SYSTEM/*pp/OmniSwitch
		rm -rf $SYSTEM/*pp/OneDrive_Samsung_v3
		rm -rf $SYSTEM/*pp/RetroMusicPlayerPrebuilt
		rm -rf $SYSTEM/*pp/SamsungCloudClient
		rm -rf $SYSTEM/*pp/SeedVault
		rm -rf $SYSTEM/*pp/Seedvault
		rm -rf $SYSTEM/*pp/Snap
		rm -rf $SYSTEM/*pp/Velvet
		rm -rf $SYSTEM/*pp/Via
		rm -rf $SYSTEM/*pp/VinylMusicPlayer
		rm -rf $SYSTEM/*pp/WellbeingPrebuilt
		rm -rf $SYSTEM/*pp/arcore
		rm -rf $SYSTEM/*pp/crDroidMusic
		rm -rf $SYSTEM/*pp/stats
		rm -rf $PRODUCT/*pp/AEXWallpaperStub
		rm -rf $PRODUCT/*pp/ARCore
		rm -rf $PRODUCT/*pp/AboutBliss
		rm -rf $PRODUCT/*pp/Abstruct
		rm -rf $PRODUCT/*pp/AudioFX
		rm -rf $PRODUCT/*pp/AudioFx
		rm -rf $PRODUCT/*pp/AudioRecorder
		rm -rf $PRODUCT/*pp/BasicDreams
		rm -rf $PRODUCT/*pp/BlissStatistics
		rm -rf $PRODUCT/*pp/BookmarkProvider
		rm -rf $PRODUCT/*pp/Browser
		rm -rf $PRODUCT/*pp/Browser2
		rm -rf $PRODUCT/*pp/Calendar
		rm -rf $PRODUCT/*pp/Chrome
		rm -rf $PRODUCT/*pp/Chrome-Stub
		rm -rf $PRODUCT/*pp/DiagnosticsToolPrebuilt
		rm -rf $PRODUCT/*pp/Drive
		rm -rf $PRODUCT/*pp/Duo
		rm -rf $PRODUCT/*pp/Email
		rm -rf $PRODUCT/*pp/EmergencyInfo
		rm -rf $PRODUCT/*pp/Etar
		rm -rf $PRODUCT/*pp/ExactCalculator
		rm -rf $PRODUCT/*pp/Exchange2
		rm -rf $PRODUCT/*pp/FM2
		rm -rf $PRODUCT/*pp/FMPlayer
		rm -rf $PRODUCT/*pp/Gallery
		rm -rf $PRODUCT/*pp/Gallery2
		rm -rf $PRODUCT/*pp/GalleryGo
		rm -rf $PRODUCT/*pp/GalleryGoPrebuilt
		rm -rf $PRODUCT/*pp/Gmail2
		rm -rf $PRODUCT/*pp/GmailGo
		rm -rf $PRODUCT/*pp/GoogleOne
		rm -rf $PRODUCT/*pp/GoogleTTS
		rm -rf $PRODUCT/*pp/GrapheneCamera
		rm -rf $PRODUCT/*pp/Jelly
		rm -rf $PRODUCT/*pp/Maps
		rm -rf $PRODUCT/*pp/Music
		rm -rf $PRODUCT/*pp/Music2
		rm -rf $PRODUCT/*pp/MusicFX
		rm -rf $PRODUCT/*pp/NavigationGo
		rm -rf $PRODUCT/*pp/OPWidget
		rm -rf $PRODUCT/*pp/Photos
		rm -rf $PRODUCT/*pp/PlayAutoInstallConfig
		rm -rf $PRODUCT/*pp/PrebuiltGmail
		rm -rf $PRODUCT/*pp/PrebuiltKeep
		rm -rf $PRODUCT/*pp/QPGallery
		rm -rf $PRODUCT/*pp/QtiSoundRecorder
		rm -rf $PRODUCT/*pp/Recorder
		rm -rf $PRODUCT/*pp/RetroMusic
		rm -rf $PRODUCT/*pp/RetroMusicPlayer
		rm -rf $PRODUCT/*pp/SatisPay
		rm -rf $PRODUCT/*pp/SeedVault
		rm -rf $PRODUCT/*pp/ShishufiedWalls
		rm -rf $PRODUCT/*pp/SimpleGallery
		rm -rf $PRODUCT/*pp/SoundAmplifierPrebuilt
		rm -rf $PRODUCT/*pp/SpeechServicesByGoogle
		rm -rf $PRODUCT/*pp/Tycho
		rm -rf $PRODUCT/*pp/Velvet
		rm -rf $PRODUCT/*pp/Via
		rm -rf $PRODUCT/*pp/Videos
		rm -rf $PRODUCT/*pp/WallpaperZone
		rm -rf $PRODUCT/*pp/WallpapersBReel2020
		rm -rf $PRODUCT/*pp/WallpapersBReel2020a
		rm -rf $PRODUCT/*pp/WellbeingPrebuilt
		rm -rf $PRODUCT/*pp/XPerienceWallpapers
		rm -rf $PRODUCT/*pp/YTMusic
		rm -rf $PRODUCT/*pp/YTMusicSetupWizard
		rm -rf $PRODUCT/*pp/YouTube
		rm -rf $PRODUCT/*pp/YouTubeMusicPrebuilt
		rm -rf $PRODUCT/*pp/arcore
		rm -rf $PRODUCT/*pp/crDroidMusic
		rm -rf $PRODUCT/*pp/facebook-appmanager
		rm -rf $PRODUCT/*pp/talkback
		rm -rf $PRODUCT/overlay/ChromeOverlay
		rm -rf $PRODUCT/overlay/TelegramOverlay
		rm -rf $PRODUCT/overlay/WhatsAppOverlay
		rm -rf $PRODUCT/*pp/AmazonAppManager
		rm -rf $PRODUCT/*pp/AncientWallpaperZone
		rm -rf $PRODUCT/*pp/AndroidAutoStub
		rm -rf $PRODUCT/*pp/AndroidAutoStubPrebuilt
		rm -rf $PRODUCT/*pp/AndroidMigratePrebuilt
		rm -rf $PRODUCT/*pp/AssistantGo
		rm -rf $PRODUCT/*pp/AudioFx_v2
		rm -rf $PRODUCT/*pp/Chrome
		rm -rf $PRODUCT/*pp/ChromeHomePageProvider
		rm -rf $PRODUCT/*pp/ClaroContenedorStub
		rm -rf $PRODUCT/*pp/DuckDuckGo
		rm -rf $PRODUCT/*pp/Eleven
		rm -rf $PRODUCT/*pp/Email
		rm -rf $PRODUCT/*pp/EmergencyInfo
		rm -rf $PRODUCT/*pp/FM2
		rm -rf $PRODUCT/*pp/FMPlayer
		rm -rf $PRODUCT/*pp/Gallery2
		rm -rf $PRODUCT/*pp/GoogleRestore
		rm -rf $PRODUCT/*pp/GoogleRestorePrebuilt
		rm -rf $PRODUCT/*pp/GuideMe
		rm -rf $PRODUCT/*pp/HelpRtcPrebuilt
		rm -rf $PRODUCT/*pp/HotwordEnrollment*
		rm -rf $PRODUCT/*pp/HotwordEnrollmentOKGoogleHEXAGON
		rm -rf $PRODUCT/*pp/HotwordEnrollmentXGoogleHEXAGON
		rm -rf $PRODUCT/*pp/MatLog
		rm -rf $PRODUCT/*pp/MusicFX
		rm -rf $PRODUCT/*pp/NovaBugreportWrapper
		rm -rf $PRODUCT/*pp/OmniSwitch
		rm -rf $PRODUCT/*pp/PixelLiveWallpaperPrebuilt
		rm -rf $PRODUCT/*pp/QtiSoundRecorder
		rm -rf $PRODUCT/*pp/RecorderPrebuilt
		rm -rf $PRODUCT/*pp/RetroMusicPlayer
		rm -rf $PRODUCT/*pp/SafetyHub
		rm -rf $PRODUCT/*pp/SafetyHubPrebuilt
		rm -rf $PRODUCT/*pp/ScribePrebuilt
		rm -rf $PRODUCT/*pp/SeedVault
		rm -rf $PRODUCT/*pp/SimpleCalendar
		rm -rf $PRODUCT/*pp/SimpleGallery
		rm -rf $PRODUCT/*pp/Snap
		rm -rf $PRODUCT/*pp/TipsPrebuilt
		rm -rf $PRODUCT/*pp/Velvet
		rm -rf $PRODUCT/*pp/VelvetGo
		rm -rf $PRODUCT/*pp/Via
		rm -rf $PRODUCT/*pp/ViaBrowser
		rm -rf $PRODUCT/*pp/VinylMusicPlayer
		rm -rf $PRODUCT/*pp/Wellbeing
		rm -rf $PRODUCT/*pp/WellbeingPreBuilt
		rm -rf $PRODUCT/*pp/WellbeingPrebuilt
		rm -rf $PRODUCT/*pp/arcore
		rm -rf $PRODUCT/*pp/crDroidMusic
		rm -rf $PRODUCT/*pp/facebook-installer
		rm -rf $PRODUCT/*pp/facebook-services
		rm -rf $PRODUCT/*pp/stats
		rm -rf $SYSTEM_EXT/*pp/EmergencyInfo
		rm -rf $SYSTEM_EXT/*pp/EmergencyInfoGoogleNoUi
		rm -rf $SYSTEM_EXT/*pp/FM2
		rm -rf $SYSTEM_EXT/*pp/FMRadioService
		rm -rf $SYSTEM_EXT/*pp/Papers
		rm -rf $SYSTEM_EXT/*pp/Photos
		rm -rf $SYSTEM_EXT/*pp/SeedVault
		rm -rf $SYSTEM_EXT/*pp/Superiorwalls
		rm -rf $SYSTEM_EXT/*pp/AndroidAutoStubPrebuilt
		rm -rf $SYSTEM_EXT/*pp/AudioFX
		rm -rf $SYSTEM_EXT/*pp/ChromeHomePageProvider
		rm -rf $SYSTEM_EXT/*pp/EmergencyInfo
		rm -rf $SYSTEM_EXT/*pp/FM2
		rm -rf $SYSTEM_EXT/*pp/Gallery2
		rm -rf $SYSTEM_EXT/*pp/GoogleRestore
		rm -rf $SYSTEM_EXT/*pp/Leaflet
		rm -rf $SYSTEM_EXT/*pp/MatLog
		rm -rf $SYSTEM_EXT/*pp/MatLog#
		rm -rf $SYSTEM_EXT/*pp/Music
		rm -rf $SYSTEM_EXT/*pp/SeedVault
		rm -rf $SYSTEM_EXT/*pp/Seedvault
		rm -rf $SYSTEM_EXT/*pp/Snap
		rm -rf $SYSTEM_EXT/*pp/WellbeingPrebuilt
		rm -rf $PRODUCT/*pp/PixelSetupWizard
		rm -rf $PRODUCT/*pp/SetupWizard
		rm -rf $PRODUCT/*pp/SetupWizardPrebuilt
		rm -rf $SYSTEM/*pp/SetupWizard
		rm -rf $SYSTEM_EXT/*pp/PixelSetupWizard
		rm -rf $SYSTEM_EXT/*pp/SetupWizard
		sleep 0.5
	fi
	set_progress 0.30
}
photo() {
		# Verifica si existe el archivo google_elite_configs.xml en la partición de product y lo elimina
	if [ -e $PRODUCT/etc/sysconfig/google_elite_configs.xml ]; then
		rm -rf $PRODUCT/etc/sysconfig/google_elite_configs.xml
	else
		rm -rf $REMOVER_PR/etc/sysconfig/google_elite_configs.xml
	fi
	rm -rf $PRODUCT/etc/sysconfig/Notice
	rm -rf $PRODUCT/etc/sysconfig/Shift.xml
	rm -rf $PRODUCT/etc/sysconfig/google_exclusives_enable.xml
	rm -rf $PRODUCT/etc/sysconfig/nga.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2022.xml
	rm -rf $PRODUCT/etc/sysconfig/pixel_experience_2022_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/nga.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $SYSTEM_EXT/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/Notice
	rm -rf $SYSTEM/etc/sysconfig/Shift.xml
	rm -rf $SYSTEM/etc/sysconfig/google_exclusives_enable.xml
	rm -rf $SYSTEM/etc/sysconfig/nga.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_2016_exclusive.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2017.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2017_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2018.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2018_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2019.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2019_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2020.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2020_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2021.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2021_midyear.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2022.xml
	rm -rf $SYSTEM/etc/sysconfig/pixel_experience_2022_midyear.xml

}# Función para preparar las herramientas y descomprimir el archivo SDKTOTAL
herramientas() {
	ui_print "* - Preparando herramientas...                   *"
	mkdir $TMP/remover   # Crea el directorio $TMP/remover
	chmod 0755 $TMP/remover   # Establece los permisos del directorio a 0755
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP   # Descomprime los archivos del directorio SDK del archivo ZIP en $TMP

	set_progress 0.40   # Establece el progreso al 40%

	# Descomprime el archivo SDKTOTAL.tar.xz en el directorio $REMOVER_FOLDER
	tar -xf "$CORE_DIR/SDKTOTAL.tar.xz" -C $REMOVER_FOLDER

	# Realiza una verificación condicional
	if [ $rem -eq 0 ]; then
		if [ $a -gt 10 ]; then
			echo "$a is even number and greater than 10."
		else
			echo "$a is even number and less than 10."
		fi
	else
		echo "$a is odd number"
	fi

	sleep 0.2
}
# Función para pre_swizard
pre_swizard() {
	# Verifica si existen ciertos archivos/directorios indicativos de MIUI
	if [ -e $SYSTEM/app/miuisystem ] || [ -e $SYSTEM_EXT/app/miuisystem ] || [ -e $SYSTEM_EXT/priv-app/MiuiSystemUIPlugin ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ] || [ -e $SYSTEM/app/miui ]; then
		rm -rf $REMOVER_PR/overlay
	else
		# Extracción de archivos relacionados con SetupProvider según la versión de Android
		if [ "$android_sdk" = 29 ]; then
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

			# Función fixrice
			fixrice() {
				if [ -e $PRODUCT/app/riceDroidThemesStub ] || [ -e $PRODUCT/app/crDroidThemesStub ]; then
					rm -rf $PRODUCT/*pp/DevicePersonalizationPrebuilt*
				fi
			}
		fi
		if [ "$android_sdk" = 33 ]; then
			rm -rf $PRODUCT/overlay/TheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/RTheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/STheGapps-Provision.apk
			rm -rf $REMOVER_PR/overlay/SLTheGapps-Provision.apk
		fi
	fi
}
# Función files
files() {
	# Instalando mods en system
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

	# Instalando mods en system_ext
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

	# Instalando mods en product
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

# Función swizard
swizard() {
	# Aplicando líneas al build para omitir setupwizard
	grep -q '^ro\.setupwizard\.mode=' "$SYSTEM_EXT/etc/build.prop" || echo 'ro.setupwizard.mode=DISABLED' >>"$SYSTEM_EXT/etc/build.prop"
	sed -i '/^ro.setupwizard.enterprise_mode/d' "$PRODUCT/etc/build.prop"
	sed -i '/^setupwizard.feature.baseline_setupwizard_enabled/d' "$PRODUCT/etc/build.prop"
	grep -q '^ro\.setupwizard\.mode=' "$SYSTEM_EXT/build.prop" || echo 'ro.setupwizard.mode=DISABLED' >>"$SYSTEM_EXT/build.prop"

	# Configuración adicional según la versión de Android
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

	# Comprobando la presencia de archivos y directorios relacionados con MIUI y Pixel Launcher
	if [ -e $SYSTEM/app/miuisystem ] || [ -e $SYSTEM_EXT/app/miuisystem ] || [ -e $SYSTEM_EXT/priv-app/MiuiSystemUIPlugin ] || [ -e $PRODUCT/app/MIUISystemUIPlugin ] || [ -e $SYSTEM/app/miui ] || [ -e $SYSTEM_ROOT/my_stock ]; then
		rm -rf $CORE_DIR/SDKPL.tar.xz
		rm -rf $CORE_DIR/SDKPL13.tar.xz
	else
		# Instalación de Pixel Launcher según la versión de Android
		if [ "$android_sdk" = 32 ]; then
			ui_print "* - Instalando Pixel Launcher v11.6...           *"
			# Configuraciones adicionales para Android 11
			grep -q '^ro\.boot\.vendor\.overlay\.static=' "$SYSTEM/build.prop" || echo 'ro.boot.vendor.overlay.static=false' >>"$SYSTEM/build.prop"
			# Eliminación de archivos y directorios relacionados con otros launchers
			rm -rf $PRODUCT/overlay/PixelLauncherCustomOverlay
			rm -rf $PRODUCT/overlay/ThemedIconsOverlay
			rm -rf $PRODUCT/overlay/PixelLauncherIconsOverlay
			rm -rf $PRODUCT/overlay/PixelRecentsProvider
			rm -rf $SYSTEM_EXT/*pp/NexusLauncherRelease
			rm -rf $PRODUCT/*pp/Lawnfeed
			rm -rf $PRODUCT/*pp/Lawnicons
			rm -rf $SYSTEM/*pp/AsusLauncherDev
			rm -rf $SYSTEM/*pp/Lawnchair
			rm -rf $SYSTEM/*pp/NexusLauncherPrebuilt
			rm -rf $PRODUCT/*pp/ParanoidQuickStep
			rm -rf $PRODUCT/*pp/ShadyQuickStep
			rm -rf $PRODUCT/*pp/TrebuchetQuickStep
			rm -rf $PRODUCT/*pp/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/*pp/DerpLauncherQuickStep
			rm -rf $SYSTEM_EXT/*pp/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/*pp/TrebuchetQuickStep

			# Extracción de archivos y directorios de la versión de Pixel Launcher
			tar -xf "$CORE_DIR/SDKPL.tar.xz" -C $REMOVER_FOLDER

			# Instalación de archivos y directorios en el sistema
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

			# Instalación de archivos y directorios en system_ext
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

			# Instalación de archivos y directorios en product
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
			sleep 0.2
		else
			rm -rf $CORE_DIR/SDKPL.tar.xz
		fi

		# Instalación de Pixel Launcher v13 para Android 12
		if [ "$android_sdk" = 33 ]; then
			ui_print "* - Instalando Pixel Launcher v13...             *"
			# Configuraciones adicionales para Android 12
			grep -q '^ro\.boot\.vendor\.overlay\.static=' "$SYSTEM/build.prop" || echo 'ro.boot.vendor.overlay.static=false' >>"$SYSTEM/build.prop"
			# Eliminación de archivos y directorios relacionados con otros launchers
			rm -rf $PRODUCT/*pp/ShadyQuickStep
			rm -rf $PRODUCT/*pp/Lawnfeed
			rm -rf $PRODUCT/*pp/Lawnicons
			rm -rf $PRODUCT/overlay/PixelLauncherCustomOverlay
			rm -rf $PRODUCT/overlay/PixelLauncher*
			rm -rf $PRODUCT/overlay/PixelLauncherIconsOverlay
			rm -rf $PRODUCT/overlay/PixelRecentsProvider
			rm -rf $PRODUCT/overlay/ThemedIconsOverlay
			rm -rf $PRODUCT/*pp/NexusLauncherRelease
			rm -rf $PRODUCT/*pp/ParanoidQuickStep
			rm -rf $PRODUCT/*pp/TrebuchetQuickStep
			rm -rf $SYSTEM/*pp/AsusLauncherDev
			rm -rf $SYSTEM/*pp/Lawnchair
			rm -rf $SYSTEM/*pp/NexusLauncherPrebuilt
			rm -rf $SYSTEM_EXT/*pp/Launcher3QuickStep
			rm -rf $SYSTEM_EXT/*pp/Lawnchair
			rm -rf $SYSTEM_EXT/*pp/NexusLauncherRelease
			rm -rf $SYSTEM_EXT/*pp/ThemePicker
			rm -rf $SYSTEM_EXT/*pp/TrebuchetQuickStep
			rm -rf $PRODUCT/*pp/DevicePersonalizationPrebuilt*
			rm -rf $PRODUCT/*pp/*evice*ersonalization*rebuilt*
			rm -rf $SYSTEM/*pp/DevicePersonalizationPrebuilt*
			rm -rf $SYSTEM_EXT/*pp/DevicePersonalizationPrebuilt*

			# Extracción e instalación de los archivos y directorios necesarios para el Pixel Launcher v13
			tar -xf "$CORE_DIR/SDKPL13.tar.xz" -C $REMOVER_FOLDER

			# Instalación de archivos y directorios en system
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

			# Instalación de archivos y directorios en system_ext
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

			# Instalación de archivos y directorios en product
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
			sleep 0.2
		else
			rm -rf $CORE_DIR/SDKPL13.tar.xz
		fi

	fi
	rm -rf $CORE_DIR
	rm -rf $REMOVER_FOLDER
}gboard() {
	mkdir $TMP/remover
	chmod 0755 $TMP/remover
	unzip -o "$ZIPFILE" 'SDK/*' -d $TMP
	ui_print "* - Instalando Gboard lite...                    *"
	# Comprueba si el directorio de temas de Gboard ya está definido en build.prop
	# Si no está definido, agrega la línea correspondiente al archivo build.prop
	if grep -q "^ro.com.google.ime.themes_dir=/system/etc/gboard_theme" "$SYSTEM/build.prop"; then
		ui_print "* - Temas previamente soportados                 *"
	else
		echo -e "ro.com.google.ime.themes_dir=/system/etc/gboard_theme" >>"$SYSTEM/build.prop"
	fi

	# Elimina los paquetes y directorios relacionados con Gboard existentes en varias particiones
	rm -rf $PRODUCT/*pp/SogouIn*
	rm -rf $PRODUCT/*pp/LatinIME
	rm -rf $PRODUCT/*pp/LatinIMEGooglePrebuilt
	rm -rf $PRODUCT/*pp/GBoard
	rm -rf $PRODUCT/*pp/EnhancedGboard
	rm -rf $PRODUCT/*pp/LatinImeGoogle
	rm -rf $PRODUCT/*pp/LatinIME
	rm -rf $SYSTEM/*pp/LatinIMEGooglePrebuilt
	rm -rf $SYSTEM_EXT/*pp/LatinIMEGooglePrebuilt
	rm -rf $PRODUCT/*pp/gboardlite_apmods
	rm -rf $SYSTEM/*pp/gboardlite_apmods
	rm -rf $SYSTEM_ROOT/my*/*pp/LatinImeGoogle

	# Extrae los archivos y directorios necesarios para Gboard Lite desde el archivo SDKG.tar.xz al directorio temporal
	tar -xf "$CORE_DIR/SDKG.tar.xz" -C $REMOVER_FOLDER

	# Obtiene la arquitectura del dispositivo
	arch=$(uname -m)

	# Comprueba si es ARMv7
	if [ "$arch" = "armv7l" ]; then
		ui_print "* - Instalando gboard version ARMv7              *"
		# Elimina el archivo base64.apk en caso de ser necesario para ARMv7
		rm -r $REMOVER_SYS/*pp/gboardlite_apmods/base64.apk
	elif [ "$arch" = "aarch64" ]; then
		ui_print "* - Instalando gboard version ARMv8              *"
		# Elimina el archivo base32.apk en caso de ser necesario para ARMv8 (aarch64)
		rm -r $REMOVER_SYS/*pp/gboardlite_apmods/base32.apk
	fi

	# Obtiene la lista de archivos y directorios en la partición system
	sys_list="$(find "$REMOVER_SYS" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_dir_list="$(find "$REMOVER_SYS" -mindepth 1 -type d | cut -d/ -f5-)"

	# Instala los archivos en la partición system, establece los permisos y el contexto de seguridad adecuados
	for file in $sys_list; do
		install -D "$REMOVER_SYS/${file}" "$SYSTEM/${file}"
		chmod 0644 "$SYSTEM/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM/${file}"
	done

	# Establece los permisos adecuados para los directorios en la partición system
	for dir in $sys_dir_list; do
		chmod 0755 "$SYSTEM/${dir}"
	done

	# Obtiene la lista de archivos y directorios en la partición system_ext
	sys_ext_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type f | cut -d/ -f5-)"
	sys_ext_dir_list="$(find "$REMOVER_SYS_EXT" -mindepth 1 -type d | cut -d/ -f5-)"

	# Instala los archivos en la partición system_ext, establece los permisos y el contexto de seguridad adecuados
	for file in $sys_ext_list; do
		install -D "$REMOVER_SYS_EXT/${file}" "$SYSTEM_EXT/${file}"
		chmod 0644 "$SYSTEM_EXT/${file}"
		chcon -h u:object_r:system_file:s0 "$SYSTEM_EXT/${file}"
	done

	# Establece los permisos adecuados para los directorios en la partición system_ext
	for dir in $sys_ext_dir_list; do
		chmod 0755 "$SYSTEM_EXT/${dir}"
	done

	# Obtiene la lista de archivos y directorios en la partición product
	pr_list="$(find "$REMOVER_PR" -mindepth 1 -type f | cut -d/ -f5-)"
	pr_dir_list="$(find "$REMOVER_PR" -mindepth 1 -type d | cut -d/ -f5-)"

	# Instala los archivos en la partición product, establece los permisos y el contexto de seguridad adecuados
	for file in $pr_list; do
		install -D "$REMOVER_PR/${file}" "$PRODUCT/${file}"
		chmod 0644 "$PRODUCT/${file}"
		chcon -h u:object_r:system_file:s0 "$PRODUCT/${file}"
	done

	# Establece los permisos adecuados para los directorios en la partición product
	for dir in $pr_dir_list; do
		chmod 0755 "$PRODUCT/${dir}"
	done

	# Elimina los directorios y archivos temporales
	rm -rf $CORE_DIR
	rm -rf $REMOVER_FOLDER
}desmontar_sistema() {
	ui_print "* - Borrando archivos temporales...              *"
	ui_print "*                                                *"
	ui_print "*               DESMONTANDO SYSTEM               *"
	sleep 0.2
	ui_print "*                                                *"

	# Intenta desmontar la partición /system
	if umount -l /system; then
		ui_print "* - Desmontado /system                           *"
	else
		ui_print "* x No desmontado /system                        *"
	fi

	# Intenta desmontar la partición /system_root
	if umount -l /system_root; then
		ui_print "* - Desmontado /system_root                      *"
	else
		ui_print "* x No desmontado /system_root                   *"
	fi

	# Verifica si la variable $PRODUCT es igual a /product y desmonta la partición correspondiente
	if [ "$PRODUCT" = /product ]; then
		if umount -l /product; then
			ui_print "* - Desmontado /product                          *"
		else
			ui_print "* x No desmontado /product                       *"
		fi
	fi

	# Verifica si la variable $VENDOR es igual a /vendor y desmonta la partición correspondiente
	if [ "$VENDOR" = /vendor ]; then
		if umount -l /vendor; then
			ui_print "* - Desmontado /vendor                           *"
		else
			ui_print "* x No desmontado /vendor                        *"
		fi
	fi

	# Verifica si la variable $SYSTEM_EXT es igual a /system_ext y desmonta la partición correspondiente
	if [ "$SYSTEM_EXT" = /system_ext ]; then
		if umount -l /system_ext; then
			ui_print "* - Desmontado /system_ext                       *"
		else
			ui_print "* x No desmontado /system_ext                    *"
		fi
	fi

	# Restaura las variables LD_LIBRARY_PATH, LD_PRELOAD y LD_CONFIG_FILE si se definieron previamente
	[ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
	[ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
	[ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG

	ui_print "*                                                *"
	ui_print "*                   REALIZADO                    *"
	ui_print "*                                                *"
	ui_print "**************************************************"
	ui_print " "
}

getDiman() {
	# Elimina los directorios y archivos relacionados con MiuiScanner, Monet, Calculator, Weather, SogouInput, Music, Aperture y Camera en varias particiones
	rm -rf $PRODUCT/*pp/MiuiScanner
	rm -rf $PRODUCT/overlay/Monet*
	rm -rf $SYSTEM/*pp/Calculator
	rm -rf $SYSTEM/*pp/*Weather*
	rm -rf $SYSTEM_EXT/*pp/*Weather*
	rm -rf $PRODUCT/*pp/*Weather*
	rm -rf $SYSTEM/*pp/SogouInput
	rm -rf $SYSTEM/*pp/Music
	rm -rf $SYSTEM/*pp/Weather
	rm -rf $SYSTEM/*pp/Aperture
	rm -rf $SYSTEM_EXT/*pp/Aperture
	rm -rf $PRODUCT/*pp/Aperture
	rm -rf $PRODUCT/*pp/*Camera*
	rm -rf $SYSTEM/*pp/*Camera*
}

creando_tmp
montando_sistema
android_version
debloater
#photo
herramientas
pre_swizard
files
swizard
#pl
#gboard
#getDiman
#fixrice
desmontar_sistema
set_progress 1.00
