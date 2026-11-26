allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Compatibility shim for AGP 9 with android.builtInKotlin=false (required while other plugins,
// e.g. firebase_*, share_plus, still apply the Kotlin Gradle Plugin themselves).
// file_picker 11.x skips KGP on AGP >= 9 because it expects built-in Kotlin, so its Kotlin
// sources were never compiled and GeneratedPluginRegistrant failed with
// "cannot find symbol FilePickerPlugin". Apply KGP to it explicitly until the app moves to
// android.builtInKotlin=true (then delete this block).
val builtInKotlinEnabled = providers.gradleProperty("android.builtInKotlin").orNull?.toBoolean() ?: true
if (!builtInKotlinEnabled) {
    subprojects {
        if (name == "file_picker") {
            plugins.withId("com.android.library") {
                apply(plugin = "org.jetbrains.kotlin.android")
                tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

// AGP 9 checks AAR metadata for library modules too: geocoding_android 3.3.1 (newest allowed by
// geocoding ^3.0.0) still compiles against android-33 while its androidx deps need >= 34.
// Raising a plugin's compileSdk only changes which APIs it compiles against, not runtime
// behaviour (targetSdk stays the plugin's / app's own), so lift old plugins to Flutter's level.
val flutterCompileSdk = 36
subprojects {
    plugins.withId("com.android.library") {
        extensions.getByType(com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java)
            .finalizeDsl { android ->
                val current = android.compileSdk
                if (current != null && current < flutterCompileSdk) {
                    android.compileSdk = flutterCompileSdk
                }
                // Lint 9.3.1 crashes with NoSuchMethodError (JavaDocParser.parseDataItem) while
                // analysing third-party plugin sources such as FlutterFirebaseCorePlugin.kt.
                // Skip release-blocking lint for plugin modules only; the app module keeps
                // lintVital (see app/build.gradle.kts).
                android.lint.checkReleaseBuilds = false
            }
        tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
