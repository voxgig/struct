plugins {
    kotlin("jvm") version "2.2.0"
    // Code quality
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
    // Maven Central publishing via the Sonatype Central Portal (+ GPG signing).
    id("com.vanniktech.maven.publish") version "0.37.0"
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

// ---- Maven Central publishing via the Sonatype Central Portal ----
// OSSRH/Nexus staging was retired 2025-06-30, so publish through the Central
// Portal with the vanniktech plugin. It builds the sources + javadoc jars,
// signs every artifact, uploads the bundle, and (automaticRelease) releases it.
// Auth comes from ORG_GRADLE_PROJECT_* env vars at release time (see Makefile):
//   mavenCentralUsername / mavenCentralPassword   Portal user token
//   signingInMemoryKey / signingInMemoryKeyPassword   ASCII-armored GPG key
// publishToMavenLocal needs no key (signing only applies to the remote publish).
mavenPublishing {
    publishToMavenCentral(automaticRelease = true)
    signAllPublications()
    coordinates("com.voxgig", "struct-kotlin", version.toString())
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
