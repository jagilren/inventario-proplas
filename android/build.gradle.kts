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
// Algunos plugins (file_picker → flutter_plugin_android_lifecycle) exigen
// compilar contra la API 36. Forzamos compileSdk 36 en todos los módulos
// Android DESPUÉS de que el plugin fije el suyo (34). El afterEvaluate se
// registra ANTES del evaluationDependsOn de abajo para no llegar tarde.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            val cur = android.compileSdkVersion
                ?.substringAfter("android-")?.toIntOrNull() ?: 0
            if (cur in 1..35) android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
