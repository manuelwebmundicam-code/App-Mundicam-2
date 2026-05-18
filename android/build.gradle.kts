// 1. Bloque de Plugins (Añadido para Firebase)
plugins {
    // Quitamos las versiones porque Flutter ya las gestiona
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("dev.flutter.flutter-gradle-plugin") apply false

    // Esta sí la dejamos con versión porque es nueva (la de Firebase)
    id("com.google.gms.google-services") version "4.4.1" apply false
}

// ... el resto del código (allprojects, val newBuildDir, etc.) igual que antes

// 2. Repositorios
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 3. Configuración de directorios de Build (Tu código original)
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

// 4. Tarea de limpieza
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}