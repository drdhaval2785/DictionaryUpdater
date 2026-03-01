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

    fun applyNamespaceWorkaround(p: Project) {
        if (p.hasProperty("android")) {
            val android = p.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            if (android.namespace == null) {
                android.namespace = "com.example.sdu.sdu.${p.name.replace("-", ".")}"
            }
            
            // AGP 8.0+ workaround: strip package attribute from manifest if it exists
            p.tasks.matching { it.name.contains("process") && it.name.contains("Manifest") }.configureEach {
                doFirst {
                    val manifestFile = android.sourceSets.getByName("main").manifest.srcFile
                    if (manifestFile.exists()) {
                        val content = manifestFile.readText()
                        if (content.contains("package=")) {
                            val newContent = content.replace(Regex("""package="[^"]+""""), "")
                            if (newContent != content) {
                                manifestFile.writeText(newContent)
                            }
                        }
                    }
                }
            }
        }
    }

    if (project.state.executed) {
        applyNamespaceWorkaround(project)
    } else {
        project.afterEvaluate {
            applyNamespaceWorkaround(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
