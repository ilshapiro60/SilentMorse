import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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
// Fix wear plugin: AGP 8+ requires namespace; align JVM targets
subprojects {
    pluginManager.withPlugin("com.android.library") {
        if (project.name == "wear") {
            project.extensions.configure<LibraryExtension> {
                namespace = "com.mjohnsullivan.flutterwear.wear"
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        if (project.name == "wear") {
            project.extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
