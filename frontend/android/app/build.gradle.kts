import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").let {
    if (it.exists()) it else project.file("key.properties")
}
val hasKeyProperties = keystorePropertiesFile.exists()

if (hasKeyProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.tenseitech.doctornect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tenseitech.doctornect"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Phone/tablet ARM only. Skips x86/x86_64 emulator ABIs that were failing
        // stripDebugDebugSymbols (missing libdartjni.so / libdatastore_shared_counter.so).
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (hasKeyProperties) {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                val resolvedStoreFile = if (storeFilePath != null) {
                    val f = file(storeFilePath)
                    if (f.exists()) f else rootProject.file(storeFilePath)
                } else null

                if (resolvedStoreFile == null || !resolvedStoreFile.exists()) {
                    gradle.taskGraph.whenReady {
                        if (allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
                            throw GradleException(
                                "FATAL: Release keystore file specified in key.properties was not found. " +
                                "Release builds must never fall back to debug signing."
                            )
                        }
                    }
                } else {
                    storeFile = resolvedStoreFile
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                }
            } else {
                gradle.taskGraph.whenReady {
                    if (allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
                        throw GradleException(
                            "FATAL: key.properties file was not found. " +
                            "Release builds must be signed with the production release keystore and will not fall back to debug signing."
                        )
                    }
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}