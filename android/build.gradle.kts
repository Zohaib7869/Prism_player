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

// Some plugins (e.g. file_picker via flutter_plugin_android_lifecycle) resolve
// Flutter's internal compileSdk default (currently 34) for their own module,
// which conflicts with their own AAR metadata requirement of 36+. Force every
// Android library subproject's compileSdk to 36 regardless of what it sets
// internally. Must run in afterEvaluate (after each plugin's own build.gradle
// sets its compileSdk) so our override actually wins, but :app is skipped
// since evaluationDependsOn above already evaluates it eagerly.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let {
                it.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}