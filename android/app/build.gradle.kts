import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { inputStream ->
        keystoreProperties.load(inputStream)
    }
}

android {
    namespace = "com.mundicam.securitydistribution"

    compileSdk = maxOf(flutter.compileSdkVersion, 35)

    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Necesario para flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.mundicam.securitydistribution"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
                ?: throw GradleException(
                    "Falta storeFile en android/key.properties"
                )

            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: throw GradleException(
                    "Falta keyAlias en android/key.properties"
                )

            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: throw GradleException(
                    "Falta keyPassword en android/key.properties"
                )

            storePassword = keystoreProperties.getProperty("storePassword")
                ?: throw GradleException(
                    "Falta storePassword en android/key.properties"
                )

            storeFile = file(storeFilePath)
        }
    }

    buildTypes {
        getByName("debug") {
            // La compilación debug mantiene la firma automática de Android.
        }

        getByName("release") {
            signingConfig = signingConfigs.getByName("release")

            // Por ahora no activamos minificación para evitar romper
            // Firebase, notificaciones o clases utilizadas dinámicamente.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )
}

flutter {
    source = "../.."
}