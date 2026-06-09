plugins {
    kotlin("jvm") version "2.2.0"
    // Code quality
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
    // Maven Central publishing + GPG signing of the published artifacts.
    `maven-publish`
    signing
}

group = "com.voxgig"
version = "0.1.0"

repositories {
    mavenCentral()
}

dependencies {
    // Gson is used ONLY by the test harness (corpus loading + assertion
    // diffs). The library proper has no third-party JSON dependency.
    testImplementation("com.google.code.gson:gson:2.11.0")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(17)
}

// ---- Code quality: detekt (static analysis) + ktlint (style) ----
detekt {
    buildUponDefaultConfig = true
    config.setFrom(files("$rootDir/detekt.yml"))
    basePath = rootDir.absolutePath
}

ktlint {
    ignoreFailures.set(false)
}

// Convenience aggregate task: `gradle lint`
tasks.register("lint") {
    group = "verification"
    description = "Runs detekt and ktlint."
    dependsOn("detekt", "ktlintCheck")
}

// ---- Maven Central publishing ----
// Attach the sources + javadoc jars that Maven Central requires. The
// kotlin("jvm") plugin wires up the `java` software component, so adding
// these here means components["java"] carries main + sources + javadoc.
java {
    withSourcesJar()
    withJavadocJar()
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            pom {
                name.set("voxgig-struct-kotlin")
                description.set(
                    "Voxgig Struct — utilities for transforming JSON-like data structures (Kotlin port).",
                )
                url.set("https://github.com/voxgig/struct")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://opensource.org/licenses/MIT")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("voxgig")
                        name.set("Voxgig")
                        organization.set("Voxgig")
                        organizationUrl.set("https://voxgig.com")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/voxgig/struct.git")
                    developerConnection.set("scm:git:git@github.com:voxgig/struct.git")
                    url.set("https://github.com/voxgig/struct")
                }
            }
        }
    }
    repositories {
        // Maven Central / OSSRH. Release vs. snapshot URL is chosen from the
        // version suffix. The matching credentials are operator-provided at
        // release time via Gradle properties (ossrhUsername / ossrhPassword)
        // or the OSSRH_USERNAME / OSSRH_PASSWORD environment variables.
        maven {
            name = "central"
            val releasesUrl =
                uri("https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")
            val snapshotsUrl =
                uri("https://s01.oss.sonatype.org/content/repositories/snapshots/")
            url = if (version.toString().endsWith("SNAPSHOT")) snapshotsUrl else releasesUrl
            credentials {
                username = (project.findProperty("ossrhUsername") as String?)
                    ?: System.getenv("OSSRH_USERNAME")
                password = (project.findProperty("ossrhPassword") as String?)
                    ?: System.getenv("OSSRH_PASSWORD")
            }
        }
    }
}

signing {
    // Only require a signing key when actually publishing to the remote
    // repository, so `publishToMavenLocal` (and ordinary builds) need no key.
    // The GPG key + passphrase are operator-provided at release time via the
    // standard signing.* Gradle properties or in-memory key env vars.
    isRequired = gradle.taskGraph.allTasks.any { it.name == "publish" }
    sign(publishing.publications["maven"])
}
