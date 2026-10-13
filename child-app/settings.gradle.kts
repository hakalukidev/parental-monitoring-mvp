pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "child-app"
include(":app")
// Synthetic notification source is never included in a production build.
if (providers.gradleProperty("seftlyQa").orNull == "true") include(":notification-fixture")
