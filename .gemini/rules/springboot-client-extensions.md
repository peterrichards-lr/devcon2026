# Spring Boot 3.x Client Extensions on Liferay Cloud

This document outlines the standard architectural conventions and learnings for compiling, configuring, and executing Spring Boot 3.x microservices natively on Liferay Cloud (PaaS) and synchronizing data dynamically into Liferay Objects.

---

## 1. Gradle Compilation (Spring Boot 3 + Java 21)

To compile Spring Boot 3.x client extensions on JDK 17/21 in Liferay Cloud without classpath conflicts:

*   **Avoid the legacy `buildscript` block** in subproject `build.gradle` files. Because Liferay Workspace core plugins are compiled for Java 8, Gradle evaluates `buildscript` blocks early using Java 8 compatibility, throwing a variant resolution error for Spring Boot 3.
*   **Always use the modern Gradle `plugins { ... }` block** to declare plugins. This resolves them dynamically using the active container JDK (Java 21):

```groovy
plugins {
    id 'java-library'
    id 'org.springframework.boot' version '3.2.1'
    id 'io.spring.dependency-management' version '1.1.4'
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}
```

---

## 2. Spring Properties & Profile Management in the Cloud

Liferay Cloud (PaaS) runs containers under environment-specific active profiles (e.g., `prod`, `dev`, `uat`). Therefore:

*   **Do not rely on `application-default.properties` for Cloud Settings.** Spring Boot ignores `default` profile properties when an active profile matching the environment is set.
*   **Define all core OAuth client registrations and `@Value` keys in `application.properties`.** This ensures they are globally registered across all profiles.
*   **Write "Indestructible" in-code fallbacks in `@Value` annotations.** Early bean initialization can crash the application context if placeholders are missing. Explicit fallbacks guarantee clean boots, while Cloud Config Trees override them automatically at runtime:

```java
@Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri:localhost}")
private String issuerUri;

@Value("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri:http://localhost:8080/o/oauth2/jwks}")
private String jwkSetUri;
```

---

## 3. High-Performance Custom Object Batch API

To synchronize large datasets (e.g. daily sales, inventory updates) dynamically and incrementally from an external Spring Boot microservice to Liferay:

*   **Avoid the generic Headless Batch Engine (`/o/headless-batch-engine/...`):** It is a file-upload multipart endpoint and requires complex `taskItemDelegateName` mapping, which frequently fails with a `NullPointerException` (delegate is null) if the custom object is modified or in draft status.
*   **Use the Custom Object's Own Dedicated Batch REST Endpoint:**
    ```http
    POST /o/c/<pluralLabel>/batch?createStrategy=UPSERT
    ```
    *   **No Delegates Required:** Because the endpoint is compiled specifically for your custom object, Liferay already has full delegate context.
    *   **Flat JSON Payload Array:** Accepts a plain, flat JSON Array of entries (no nested `"values"` structure required).
    *   **UPSERT Strategy:** Appending `?createStrategy=UPSERT` enables idempotent inserts/updates. If a record carrying an `externalReferenceCode` (ERC) already exists, Liferay updates it; otherwise, Liferay inserts a new record.

---

## 4. Key OAuth Scopes for Custom Objects

To read and write Custom Object records securely, ensure your client extension's `client-extension.yaml` requests the dedicated **Object REST** scopes:

```yaml
scopes:
    - Liferay.Headless.Object.everything # Read schema metadata
    - Liferay.Object.REST.everything     # Read and Write custom object entries
    - C_MOTORBIKESALESRECORD.everything  # Specific published Object permission scope
```

*Note: In Liferay DXP, redeploying `client-extension.yaml` does not automatically check newly added scopes in already-registered OAuth profiles. You must manually check the scopes and map the Service Account User to an Admin account in Control Panel ➔ OAuth 2 Administration.*
