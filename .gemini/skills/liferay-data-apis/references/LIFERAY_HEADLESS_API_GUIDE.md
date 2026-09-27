# Liferay Headless API Guide

This guide details specific nuances, workarounds, and best practices when interacting with Liferay's Headless APIs, specifically focusing on User Accounts, Roles, and Account Onboarding.

## 1. Fetching User Roles (The `my-user-account` Endpoint)

When fetching the current user's profile via `/o/headless-admin-user/v1.0/my-user-account`, Liferay does not return a simple flat array of all roles a user holds. 

Instead, roles are strictly scoped and nested based on where they are assigned. If you need to verify if a user has a specific role (e.g., "Ricoh Dealer"), you must recursively or broadly flatten the arrays across all possible contexts:

```javascript
const userUrl = '/o/headless-admin-user/v1.0/my-user-account';
const userData = await Liferay.Util.fetch(userUrl).then(res => res.json());

// Flatten all possible role locations
const allRoles = [
    ...(userData.roleBriefs || []), // Global roles
    ...(userData.accountBriefs || []).flatMap(acc => acc.roleBriefs || []), // Account roles
    ...(userData.organizationBriefs || []).flatMap(org => org.roleBriefs || []), // Organization roles
    ...(userData.siteBriefs || []).flatMap(site => site.roleBriefs || []), // Site roles
    ...(userData.userGroupBriefs || []).flatMap(ug => ug.roleBriefs || []) // User Group roles
];

const hasSpecificRole = allRoles.some(role => role.name === 'Ricoh Dealer');
```

## 2. Onboarding an Account via Headless APIs

Creating an account, assigning an address, and granting a user access requires specific schema compliance.

### A. Creating the Account
Standard `POST` to `/o/headless-admin-user/v1.0/accounts`.

```json
{
    "name": "Company Name",
    "type": "business",
    "status": 0,
    "taxId": "12345678"
}
```

### B. Adding a Postal Address
When adding an address via `/o/headless-admin-user/v1.0/accounts/{accountId}/postal-addresses`, Liferay enforces strict validation against its internal dictionaries:
- **`addressCountry`**: Must perfectly match the `name` or `name_i18n` in Liferay (e.g., `"United Kingdom"`, NOT `"GB"` or `"united-kingdom"`).
- **`addressRegion`**: Must perfectly match the Liferay region dictionary. For the UK, this is very strict (e.g., `"London, City of"`, NOT `"Greater London"`). If a third-party API like Google Places provides a region that doesn't match Liferay's strict list, the request will fail with a `400 BAD REQUEST` ("Region not found"). It is highly recommended to wrap address creation in a `try/catch` block so a region mismatch does not crash the entire onboarding flow.
- **`addressType`**: Must match an existing Liferay List Type exactly (lowercase, e.g., `"billing"`, `"shipping"`).

### C. Assigning a User to the Account
You **cannot** use the ID-to-ID endpoint for associating an existing user with a new account via standard POST mapping. 
Instead, you must link them using the email endpoint:
```javascript
// Correct
await Liferay.Util.fetch(`/o/headless-admin-user/v1.0/accounts/${accountId}/user-accounts/by-email-address/${userEmail}`, { method: 'POST' });

// Incorrect (Will return 405 Method Not Allowed)
// await Liferay.Util.fetch(`/o/headless-admin-user/v1.0/accounts/${accountId}/user-accounts/${userId}`, { method: 'POST' });
```

### D. Assigning Account Roles
After the user is linked to the account, you can grant them Account Roles (such as Account Administrator). The most reliable endpoint is assigning by the role's External Reference Code (ERC) mapped against the user's ID.
```javascript
await Liferay.Util.fetch(`/o/headless-admin-user/v1.0/accounts/${accountId}/account-roles/by-external-reference-code/ACCOUNT_ADMINISTRATOR/user-accounts/${userId}`, {
    method: 'POST'
});
```

### E. Assigning to Account Groups
To organize accounts into segments (e.g., for pricing or visibility), you can assign them to Account Groups. Using the ERC-based endpoint is recommended for robustness.

```javascript
// Assign account to group using ERCs
await Liferay.Util.fetch(`/o/headless-admin-user/v1.0/account-groups/by-external-reference-code/${groupErc}/accounts/by-external-reference-code/${accountErc}`, {
    method: 'POST'
});
```

## 3. Fetching and Filtering Commerce Orders

When building custom order dashboards or details fragments, you often need to fetch orders specifically for the current Commerce Account.

### A. Getting the Current Account ID
Use the `Liferay.CommerceContext` object (available in the browser) to get the `accountId`.

```javascript
if (Liferay.CommerceContext && Liferay.CommerceContext.account) {
    const accountId = Liferay.CommerceContext.account.accountId;
}
```

### B. Fetching Orders with Nested Items
To get full order details including line items in a single request, use the `nestedFields=orderItems` parameter.

**Endpoint:** `/o/headless-commerce-admin-order/v1.0/orders?nestedFields=orderItems&pageSize=100`

### C. Client-Side Filtering by Account ID
Currently, the `headless-commerce-admin-order` API does not always support direct `filter=accountId eq ...` queries depending on the Liferay version and permissions. A reliable pattern is to fetch the latest orders and filter them client-side:

```javascript
const ordersUrl = `/o/headless-commerce-admin-order/v1.0/orders?nestedFields=orderItems&pageSize=100`;
const ordersData = await Liferay.Util.fetch(ordersUrl).then(res => res.json());

// Filter by the accountId from Liferay.CommerceContext
const accountOrders = ordersData.items.filter(order => order.accountId == accountId);
```

## 4. Linking Orders to Custom Objects

A powerful pattern for B2B applications (like Ricoh Finance) is linking standard Commerce Orders to custom Liferay Objects (e.g., "Finance Originations").

### A. Relationship Naming Convention
Custom object relationships follow a specific naming pattern in the API: `r_<sourceObject>To<targetObject>_<targetObjectIdField>`.

**Example:**
If a `FinanceOrigination` object has a relationship to a `CommerceOrder`, the field in the `financeoriginations` API response will likely be:
`r_commerceOrderToFinance_commerceOrderId`

### B. Matching Data Client-Side
Fetch both datasets and use the relationship field to join them:

```javascript
const financeData = await Liferay.Util.fetch('/o/c/financeoriginations?pageSize=100').then(res => res.json());
const financeItems = financeData.items || [];

// Inside your order loop:
const matchingFinance = financeItems.find(f => f.r_commerceOrderToFinance_commerceOrderId == order.id);
```

## 5. Unauthenticated Guest Access & Service Access Policies (SAP)

By default, Liferay Headless APIs block unauthenticated (Guest) requests. If you are building fragments or front-end components meant for public pages, you MUST configure a **Service Access Policy (SAP)**.

### Configuring the SAP
1. Navigate to **Global Menu &rarr; Control Panel &rarr; Security &rarr; Service Access Policy**.
2. Click **Add** to create a new policy.
3. Configure the following critical settings:
   - **Enabled:** Checked
   - **Default:** Checked *(This is required to apply the policy to unauthenticated/guest users automatically).*
   - **Title:** e.g., "Guest Headless Delivery Access"
4. Switch to **Advanced Mode** at the bottom of the page.
5. In the **Allowed Service Signatures** box, add the fully qualified implementation signatures required for your use case.

**Common Signatures for Public Sites:**

To allow guests to fetch individual Web Content Articles (Structured Content):
```text
com.liferay.headless.delivery.internal.resource.v1_0.StructuredContentResourceImpl#getStructuredContent
```

To allow guests to fetch Navigation Menus via the Headless API:
```text
com.liferay.headless.delivery.internal.resource.v1_0.NavigationMenuResourceImpl#getNavigationMenu
```

*Note: You must also ensure the actual resource (e.g., the Web Content Article) has its View permissions granted to the Guest role.*

## 6. Dynamic Fragment Integration via Headless API

When building custom UI fragments that rely on complex data (like Geolocation fields which cannot be mapped natively via `data-lfr-editable-type="html"`), you can use the Headless API to dynamically fetch and inject the data client-side.

### Example: Google Maps Integration via URL Path Parsing

If a fragment sits on a Display Page Template, it lacks direct FreeMarker access to the underlying structured content's ID in the browser. You can parse the URL to extract the Content ID and make an API call to retrieve the necessary fields (like latitude and longitude).

```javascript
(function() {
    const iframe = fragmentElement.querySelector('.dynamic-map');

    // 1. Abort if inside Liferay Site Builder edit mode to prevent breaking the editor
    if (document.body.classList.contains('has-edit-mode-menu') || document.querySelector('[data-editor-enabled="true"]')) {
        return;
    }

    // 2. Extract the Structured Content ID from the last segment of the Display Page URL
    const pathSegments = window.location.pathname.split('/').filter(Boolean);
    const contentId = pathSegments[pathSegments.length - 1];

    if (contentId && !isNaN(contentId)) {
        // 3. Securely fetch the article details using Liferay's built-in utility (handles CSRF/Auth automatically)
        Liferay.Util.fetch(`/o/headless-delivery/v1.0/structured-contents/${contentId}`)
            .then(response => {
                if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                return response.json();
            })
            .then(data => {
                // 4. Extract the nested geolocation field
                if (data.contentFields) {
                    const geoField = data.contentFields.find(f => f.name === 'geolocationOfPrimaryHomeCourse');
                    if (geoField && geoField.contentFieldValue && geoField.contentFieldValue.geo) {
                        const lat = geoField.contentFieldValue.geo.latitude;
                        const lng = geoField.contentFieldValue.geo.longitude;
                        
                        // 5. Update the iframe source
                        iframe.src = `https://www.google.com/maps/embed/v1/view?key=YOUR_API_KEY&center=${lat},${lng}&zoom=14`;
                    }
                }
            })
            .catch(err => console.error("Failed to fetch data:", err));
    }
})();
```

## 7. Organization of Files inside Liferay New CMS UI (The `CMSBasicDocument` Object)

When working with Liferay's new React-based CMS UI (Files tab), documents and media files are managed as entries of the system object `CMSBasicDocument` (API endpoint context path: `/cms/basic-documents/`).

### A. The Challenge with Standard Media Uploads
If you upload files to Liferay Documents & Media using standard REST endpoints (e.g. `POST /o/headless-delivery/v1.0/sites/{siteId}/documents` or `/document-folders/{folderId}/documents`), the files are stored inside Liferay's standard Documents system. However, they will **not automatically appear** inside the new React-based CMS UI "Files" folder structure!

### B. The Solution: Direct `CMSBasicDocument` Creations
To ensure files are properly indexed and show up instantly inside the new CMS UI, you should POST them directly as `CMSBasicDocument` object entries using Base64 encoding.

**Endpoint:** `POST /o/cms/basic-documents/scopes/{scopeKey}`

**Payload Structure:**
```json
{
  "title": "course_syllabus.pdf",
  "title_i18n": {
    "en_US": "course_syllabus.pdf"
  },
  "file": {
    "fileBase64": "JVBERi0xLjQKJbXtr...", // Base64-encoded file string
    "name": "course_syllabus.pdf"
  },
  "objectEntryFolderId": 40373 // The numeric ID of your target CMS ObjectEntryFolder
}
```

### C. Locating the Target `ObjectEntryFolder` ID
The new CMS UI organizes files using `ObjectEntryFolder`s. These folders have their own alphanumeric `externalReferenceCode`. 
To retrieve the numeric `objectEntryFolderId` required by the payload, list existing documents in `/o/cms/basic-documents/scopes/{scopeKey}`:
```javascript
Liferay.Util.fetch(`/o/cms/basic-documents/scopes/${scopeKey}`)
  .then(res => res.json())
  .then(data => {
      // Find the folder mapping by looking at an existing document inside the target folder
      const sampleDoc = data.items.find(item => item.objectEntryFolderExternalReferenceCode === "90422e3b-114e-3643-f3cd-e08e09a97c4a");
      const folderId = sampleDoc ? sampleDoc.objectEntryFolderId : null;
      console.log("Folder Numeric ID:", folderId); // e.g. 40373
  });
```

### D. Updating Custom Object Fields
Once created as a `CMSBasicDocument`, the returned entry `id` (e.g., `41451`) should be referenced in any custom Object fields (such as `courseSheet` of type `FileEntry`):
```json
{
  "courseSheet": {
    "id": 41451
  }
}
```

```

## 8. Resolving Localized Field Validation Errors ("No value was provided for the language ID")

When performing POST operations on Liferay custom objects with required localized fields (such as `title` or `summary`), you may encounter a misleading and frustrating validation error:

```json
{
  "status" : "BAD_REQUEST",
  "title" : "No value was provided for the language ID \"en_US\" in the required object field \"title\"."
}
```

This error can occur even if you have populated both `"title"` and `"title_i18n"` with `"en_US"` keys correctly.

### A. The Root Cause: Nested Relationship Mapping during Creation
The underlying issue is often **not** the localization payload itself, but trying to associate relationships inline inside the creation POST payload:
```json
// This inline relationship array can corrupt the JSON deserializer's locale context!
"name7252b11db32e4f01aeb20124": [
  { "externalReferenceCode": "985e77f1-db4a-599a-3cb0-865df0fdc7a9" }
]
```
When a relationship list is sent during creation, Liferay's nested deserializer intercepts the JSON parsing context. This causes the main entry's localized fields to fail validation under Liferay's default locale (e.g. `en_US` with underscore), resulting in the validation crash.

### B. The Workaround: Sequential Creation & Linking (Mandatory Pattern)
To bypass this deserialization bug, always separate creation and relationship linking into a **strict two-step sequence**:

1. **Step 1: Create the Object Entry without Relationships**
   POST the creation payload containing ONLY the object's properties. Do not include any relationship fields or arrays.
   ```json
   POST /o/c/elearningmodules/scopes/37453
   {
     "title": "UX Research and Discovery",
     "title_i18n": {
       "en_US": "UX Research and Discovery"
     },
     "summary": "<p>Master user interviewing and persona development.</p>",
     "summary_i18n": {
       "en_US": "<p>Master user interviewing and persona development.</p>"
     },
     "moduleNumber": 1,
     "numberOfLessons": 4,
     "duration": "5 days",
     "duration_i18n": {
       "en_US": "5 days"
     }
   }
   ```
   *Note: Standard locales in Liferay payloads use underscores (e.g. `"en_US"`, `"es_ES"`), matching Liferay's database locale strings.*

2. **Step 2: Associate the Relationship via PUT**
   Take the returned object entry `id` (e.g., `40807`) and call the dedicated relationship link endpoint, passing an empty JSON body `{}` to satisfy content-length requirements:
   ```json
   PUT /o/c/elearningmodules/40807/name7252b11db32e4f01aeb20124/40468
   {}
   ```

### C. Underscores (`_`) vs. Hyphens (`-`) in Locales
- **Inside JSON Payloads (`_i18n` fields)**: Always use the underscore-separated locale string (e.g., `"en_US"`, `"pt_BR"`, `"es_ES"`), which matches Liferay's internal portal locale strings.
- **Inside HTTP Headers (`Accept-Language`)**: When specifying language headers, use the standard BCP 47 hyphen-separated format (e.g., `Accept-Language: en-US`).

## 9. Object-Based Structured Content in the New Liferay CMS (The Modern Paradigm)

Liferay's modern CMS implements **Structured Content** (the "First Paradigm") directly as **Liferay Objects**. In this paradigm, content types are defined as custom or system Object definitions, which inherit robust localization, folder hierarchy, and asset library scoping features.

### A. Core Architectural Pillars
When creating, updating, or querying structured content in the new CMS, three core attributes are paramount:
1. **`scopeKey` (The Space Reference)**: Defines the context or "Space" (e.g., a specific Asset Library or Site) where the CMS content resides. E.g., `"scopeKey": "SolaraHub"`.
2. **`objectEntryFolderId` / `objectEntryFolderExternalReferenceCode`**: Maps the entry to a specific Folder to organize the content within the CMS UI tree hierarchy.
3. **`title` (always mandatory)**: Every CMS structured content entry must define a localized title, both as a flat string property and mapped under `"title_i18n"`.

### B. Standard Endpoints
Every custom structured content object (e.g. `generalopinions`) exposes the following endpoints:

* **GET (List Approved Content in Scope)**: `GET /o/c/{pluralLabel}/scopes/{scopeKey}/approved`
  * *Example:* `/o/c/generalopinions/scopes/SolaraHub/approved`
* **GET (List Draft Content in Scope)**: `GET /o/c/{pluralLabel}/scopes/{scopeKey}/draft`
* **POST (Create in Scope Folder)**: `POST /o/c/{pluralLabel}/scopes/{scopeKey}`
* **PUT (Replace Entry)**: `PUT /o/c/{pluralLabel}/{id}`
* **PATCH (Surgically Update Entry)**: `PATCH /o/c/{pluralLabel}/{id}`
* **DELETE (Remove Entry)**: `DELETE /o/c/{pluralLabel}/{id}`

### C. Reference Schema Example
The following is an exact representation of an approved CMS structured content item from the `generalopinions` API:

```json
{
  "id": 68589,
  "externalReferenceCode": "13199b67-f293-b828-71ba-2b6045783f8d",
  "scopeKey": "SolaraHub",
  "scopeId": 57817,
  "objectEntryFolderId": 68577,
  "objectEntryFolderExternalReferenceCode": "cd846bbc-e9fb-5fca-f8c9-ecdefa35cf10",
  "status": {
    "code": 0,
    "label": "approved"
  },
  "title": "Marko K.",
  "title_i18n": {
    "en_US": "Marko K."
  },
  "opinion": "Rode 4,200km across Europe in 3 weeks. The TR500 never leaked, never rattled. Fitting was 45 minutes on my GS.",
  "opinion_i18n": {
    "en_US": "Rode 4,200km across Europe in 3 weeks. The TR500 never leaked, never rattled. Fitting was 45 minutes on my GS."
  },
  "stars": 5,
  "usercategory": {
    "key": "AdventureRides",
    "name": "Adventure Rides"
  }
}
```

### D. Multi-action Capability Mapping
Object-based CMS contents expose rich operation hrefs directly inside their individual items' `"actions"` map (e.g., `move`, `move-replace`, `duplicate`, `copy`, `copy-replace`, `expire`, `versions`).

### E. Handling Picklist / Select Fields in New CMS Object Structures

When a custom CMS structure contains a **Picklist** field (such as a `usercategory` field), the modern Liferay Objects engine handles validation, retrieval, and mapping differently than standard attributes:

1. **How Picklist Values are Retrieved (GET)**:
   The GET response returns the selected picklist entry as a nested object containing both its unique identifier `key` and its default `name`:
   ```json
   "usercategory" : {
     "key" : "AdventureRides",
     "name" : "Adventure Rides"
   }
   ```

2. **How Picklist Values are Set/Created (POST/PUT/PATCH)**:
   When creating or updating an entry with a picklist field, do not send a raw string. Instead, send a nested object specifying the target picklist entry **`key`**:
   ```json
   "usercategory": {
     "key": "AdventureRides"
   }
   ```

3. **Locating Valid Picklist Keys and Definitions**:
   If you need to discover valid options (keys and names) for a picklist field but only know the picklist's name, you can retrieve all registered picklists and their embedded entries by querying Liferay's global list-type definition endpoint:
   * **Endpoint:** `GET /o/headless-admin-list-type/v1.0/list-type-definitions`
     *(Full URL: `https://solaramoto.com/o/headless-admin-list-type/v1.0/list-type-definitions`)*
   
   This endpoint lists every picklist on the portal, including its nested `listTypeEntries` array, exposing the unique `"key"` and default `"name"` for each valid choice.

## 10. Liferay Collaboration & Project Management (CMP) Dynamic Space Paradigm

Liferay’s Collaboration & Project Management (CMP) system is built fully on top of **Liferay Objects** and operates on a highly specific **Dynamic Space Generation** and **Cross-Space Asset Linking** model. Understanding this model is mandatory for creating, querying, or linking projects, tasks, and project assets.

### A. The Paradigm: Dedicated Automatically-Generated Spaces
The core architectural rule of CMP is that **every Project has its own dedicated physical Space (Asset Library context)**.
1. **Dynamic Generation**: When a project is created at the root level, Liferay triggers an active `ObjectEntryModelListener` that automatically provisions a dedicated Liferay Group (Asset Library) named identically to the project's `title`.
2. **Context Key**: The unique identifier of this newly provisioned Asset Library space is captured inside the project record's **`scopeKey`** attribute (e.g. `"scopeKey": "wXLX8gM8"`).
3. **Scoping Isolation**: To keep task management and team collaborations isolated, **every task related to that project must be created and scoped strictly inside that automatically generated space (under the project's specific `scopeKey`)**.

### B. The Cross-Space Asset Linking Paradigm
While tasks are strictly local to the project space, **linked assets/documents (represented by `cmp-project-links` or `cmpprojectlinks`) can reside either locally in the project space OR externally inside other Liferay spaces** (such as parent sites or other asset libraries like `"CS 26"` / `"L_CMS"`).

To accomplish this cross-space decoupling, every Project Link entry lives locally inside the project's space (`"scopeKey": "wXLX8gM8"`) but holds three critical pointer properties to refer to the target asset:
1. **`className`**: Defines the target asset's type/model.
   * *Example:* `"com.liferay.object.model.ObjectDefinition#H4T4"`
2. **`classExternalReferenceCode`**: Holds the unique `externalReferenceCode` of the target asset itself.
   * *Example:* `"modernizing-enterprise-digital-architecture-key-architectural-considerations-for-technical-teams"`
3. **`groupExternalReferenceCode`**: Points to the `externalReferenceCode` of the **Space (Site or Asset Library) where the target asset physically resides**.
   * *If the asset is local to the project space:* This points to the project's own generated space.
   * *If the asset is external (e.g., in "CS 26"):* This points to that external space’s ERC (e.g. `"ca74e4cb-1af9-79c1-913b-224f9d482854"`).

This highly flexible model allows the CMP Assets UI to seamlessly display and reference shared materials, global technical specs, and local project drafts in a single unified list.

### C. Standard Endpoints
CMP Projects, Tasks, and Project Links expose standard Liferay Headless Object REST paths:

#### 1. CMP Projects (`cmp-projects` / plural label: `cmpprojects`)
* **GET Project by ID**: `GET /o/c/cmpprojects/{projectId}`
* **POST Create Project**: `POST /o/c/cmpprojects` (Note: Created at the root; Liferay then provisions the space).
* **GET Project List in Space**: `GET /o/c/cmpprojects/scopes/{scopeKey}`

#### 2. CMP Tasks (`cmp-tasks` / plural label: `cmptasks`)
* **POST Create Task in Project Space**: `POST /o/c/cmptasks/scopes/{scopeKey}`
* **GET Tasks in Project Space**: `GET /o/c/cmptasks/scopes/{scopeKey}`
* **GET/PUT/PATCH/DELETE Task**: `/o/c/cmptasks/{taskId}`

#### 3. CMP Project Links / Assets (`cmp-project-links` / plural label: `cmpprojectlinks`)
* **GET Assets inside Project Space**: `GET /o/c/cmpprojectlinks/scopes/{scopeKey}`

### D. Live Reference Model: Project `65390` ("CS Brasil 2026")
The following is an exact representation of your live Project record retrieved from `GET /o/c/cmpprojects/65390`:

```json
{
  "id": 65390,
  "title": "CS Brasil 2026",
  "scopeId": 65388,
  "scopeKey": "wXLX8gM8",
  "state": {
    "key": "notStarted",
    "name": "Not Started"
  },
  "completionRate": 50,
  "systemProperties": {
    "scope": {
      "type": "AssetLibrary",
      "externalReferenceCode": "549a1362-8b97-ae66-7da6-e9de94088219"
    }
  }
}
```

#### Corresponding Project Tasks (Scoped inside Project Space `"wXLX8gM8"`):
```json
[
  {
    "id": 65430,
    "title": "Criar 5 Novos Produtos",
    "scopeKey": "wXLX8gM8",
    "r_cmpProjectToCMPTasks_c_cmpProjectId": 65390,
    "state": {
      "key": "done",
      "name": "Done"
    }
  },
  {
    "id": 65622,
    "title": "Novos Produtos",
    "scopeKey": "wXLX8gM8",
    "r_cmpProjectToCMPTasks_c_cmpProjectId": 65390,
    "state": {
      "key": "inProgress",
      "name": "In Progress"
    }
  }
]
```

#### Corresponding Project Links / Assets (Scoped inside Project Space `"wXLX8gM8"`):
The Project has **6 distinct assets** scoped within `"scopeKey": "wXLX8gM8"`, linked back via `"r_cmpProjectToCMPProjectLinks_c_cmpProjectId": 65390`, each referencing standard system objects (e.g. structured content articles on architecture like `"com.liferay.object.model.ObjectDefinition#H4T4"`):
```json
{
  "id": 67847,
  "title": "Modernizing Enterprise Digital Architecture",
  "scopeKey": "wXLX8gM8",
  "className": "com.liferay.object.model.ObjectDefinition#H4T4",
  "classExternalReferenceCode": "modernizing-enterprise-digital-architecture-key-architectural-considerations-for-technical-teams",
  "groupExternalReferenceCode": "ca74e4cb-1af9-79c1-913b-224f9d482854",
  "r_cmpProjectToCMPProjectLinks_c_cmpProjectId": 65390
}
```

### E. Avoiding Relational Validation Traps: The Flat-Pointer Seeding Pattern

When creating or seeding objects that have **one-to-many or many-to-many relationships** (like CMP Tasks, Project Links, or Task Links) through Headless REST or Liferay MCP, the API schema may declare the relationship properties (e.g. `cmpProjectToCMPTasks` or `cmpTaskToCMPTaskLinks`) as **required** and describe them as nested objects of the related model:

#### 1. The Trap: Inline Relationship Objects
If you attempt to satisfy the schema by passing the relationship field as a nested JSON object (even with just the primary ID, e.g. `"cmpTaskToCMPTaskLinks": {"id": 69031}`), Liferay’s nested deserializer will attempt to **inline create or update** the related object.
This triggers two severe failure modes:
*   **Missing Fields Error**: If you omit required fields of the related model (like `title`), Liferay’s schema validator will throw an HTTP `400 Bad Request` (e.g. `"No value was provided for required object field 'title'"`).
*   **Server Database Crash**: If you populate all required fields to satisfy the validator, the engine will attempt to write/update the related object. Since that object already exists, the database unique constraints will crash, throwing an HTTP `500 Internal Server Error`.

#### 2. The Solution: The Flat-Pointer Seeding Pattern
To bypass nested schema validation and avoid database deserialization conflicts completely, **always completely omit the nested relationship objects from your POST creation payloads**.

Instead, supply only the flat, direct, decoupled reference pointer fields of the relationship:
*   **Numeric ID Pointer**: `r_<relationshipName>_c_<targetModel>Id` (Integer)
*   **External Reference Code Pointer**: `r_<relationshipName>_c_<targetModel>ERC` (String)
*   **Relationship Base ERC**: `<relationshipName>ERC` (String)

#### 3. Critical Front-End Rendering Rule: System-Generated Class Names
When creating relationship links (like `cmp-project-links` or `cmp-task-links`), you must supply a **`className`** field to identify the type of the target asset.

*   **The Gotcha**: Liferay’s underlying Object database registers custom/system definitions using **system-generated short codes** (e.g., `#Z7P5`) rather than their literal schema names (e.g., `#L_CMS_BASIC_DOCUMENT`). 
*   **The Failure Mode**: If you use the literal schema name (e.g., `"com.liferay.object.model.ObjectDefinition#L_CMS_BASIC_DOCUMENT"` or `"com.liferay.document.library.kernel.model.DLFileEntry"`), the link creation will succeed with an HTTP `200 OK` in the database, but **Liferay's React-based front-end CMP UI will fail to match the class and render the assets as blank/empty in the Tasks panel**.
*   **The Resolution**: Always inspect working samples on the portal to retrieve the active system-generated short code. On this active portal, the unique key representing the **CMS Basic Document (`L_CMS_BASIC_DOCUMENT`)** definition is strictly **`Z7P5`**.

##### Perfect Example for Task Links:
```json
{
  "className": "com.liferay.object.model.ObjectDefinition#Z7P5",
  "classExternalReferenceCode": "60694cd3-b980-a531-eb0a-9c4b9c694188",
  "groupExternalReferenceCode": "50521773-1852-0cfd-cc5f-7b504cff88e4",
  "r_cmpTaskToCMPTaskLinks_c_cmpTaskId": 69031,
  "r_cmpTaskToCMPTaskLinks_c_cmpTaskERC": "aed9a909-245e-9e4d-67ab-7ae0d57cea2f",
  "cmpTaskToCMPTaskLinksERC": "aed9a909-245e-9e4d-67ab-7ae0d57cea2f"
}
```

This flat-pointer pattern combined with the correct system-generated short code is 100% supported by Liferay’s underlying Object engine and guarantees flawless, beautiful rendering inside Liferay's CMP front-end panels!

```

