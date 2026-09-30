# Guide: Batch Client Extensions for Object Initialization

This document summarizes the verified configuration and folder structure required to successfully initialize Liferay Objects and place them into custom folders using Batch Client Extensions (CX).

Batch CX should not be mixed with Custom Element CX in the same CX project or share the same client-extension.yaml.


## 1. Project Structure
The project should use the `assemble` block to bundle all definitions:
```
client-extensions/[project-name]/
├── client-extension.yaml
├── bnd.bnd
└── batch/
    ├── 01-00-folder-definition.batch-engine-data.json
    └── 01-01-object-definition.batch-engine-data.json
```

## 2. Configuration Patterns

### Execution Order
The Liferay Batch Engine processes files alphabetically. Use numeric prefixes to ensure dependencies are met:
- `01-00-...`: Folders (must exist before objects).
- `01-01-...`: Object Definitions.
- `02-00-...`: Relationships.
- `03-00-...`: Entries/Data.

### `client-extension.yaml`
Key requirements:
- **Assemble**: Copy the entire folder into `batch`.
- **OAuth Server**: Provide `.serviceAddress` and `.serviceScheme` to avoid validation errors.
- **Scopes**: Ensure at least `Liferay.Headless.Batch.Engine.everything` and `Liferay.Object.Admin.REST.everything` are included.

```yaml
assemble:
    - from: batch
      into: batch

my-batch-init:
    name: My Batch Initialization
    oAuthApplicationHeadlessServer: my-batch-oauth-server
    type: batch

my-batch-oauth-server:
    .serviceAddress: localhost:8080
    .serviceScheme: http
    name: My Batch OAuth Server
    scopes:
        - Liferay.Headless.Batch.Engine.everything
        - Liferay.Object.Admin.REST.everything
    type: oAuthApplicationHeadlessServer
```

### Folder Definition (`01-00-...json`)
Use the REST DTO class: `com.liferay.object.admin.rest.dto.v1_0.ObjectFolder`.
```json
{
  "configuration": {
    "className": "com.liferay.object.admin.rest.dto.v1_0.ObjectFolder",
    "parameters": {
      "createStrategy": "UPSERT",
      "updateStrategy": "UPDATE"
    }
  },
  "items": [
    {
      "name": "MyFolder",
      "label": { "en_US": "My Custom Folder" },
      "externalReferenceCode": "MY_CUSTOM_FOLDER_ERC"
    }
  ]
}
```

### Object Definition (`01-01-...json`)
Key fields for success:
- **`className`**: `com.liferay.object.admin.rest.dto.v1_0.ObjectDefinition`.
- **`objectFolderExternalReferenceCode`**: Link to the folder defined above.
- **`scope`**: `company` for system-wide, `site` for specific site.
- **`status`**: Must be `{"code": 0, "label": "approved"}` to be active immediately.
- **`enableCategorization`**: Set to `true` to allow Liferay Categories to be used with entries.
- **`enableObjectEntryVersioning`**: For **CMS Content Structures** (`objectFolderExternalReferenceCode: "L_CMS_CONTENT_STRUCTURES"`), `"enableObjectEntryVersioning": true` alongside `"portlet": true` is **mandatory** for UI deletion to work (otherwise bulk delete preview returns 404). Once published with versioning, Liferay does not allow disabling versioning on an existing definition. Custom `title` fields must have `"system": false` to remain editable and display properly in the CMS UI.
- **`objectFields`**: Ensure custom fields for commerce filtering have `indexed: true` and `indexedAsKeyword: true`.

### Data Population (`03-00-...json`)
When importing actual entries into a custom object, use the `ObjectEntry` DTO.

Key requirements:
- **`className`**: `com.liferay.object.rest.dto.v1_0.ObjectEntry`.
- **`taskItemDelegateName`**: Must match the **Object Name** (e.g., `C_MyObject`).
- **`externalReferenceCode`**: Crucial for `UPSERT` strategy to avoid duplicates and for linking to Commerce products.
- **`values`**: A dictionary containing the actual field names and their values.

#### Advanced Mapping Patterns
- **Relationships (ERC Resolution)**: This is the **preferred method** for portable deployments. You do not need the internal ID. Use the relationship's camelCase name as the key, and an object containing the target `externalReferenceCode`.
  - **Single Relationship**:
    ```json
    "relationshipName": { "externalReferenceCode": "PARENT-ERC-001" }
    ```
  - **Many-to-Many Relationship**:
    ```json
    "relationshipName": [
      { "externalReferenceCode": "REL-ERC-01" },
      { "externalReferenceCode": "REL-ERC-02" }
    ]
    ```
    > **Validation Note on Required Fields**: During batch import, Liferay's DTO validator validates each nested entry against the target object's schema. If the target object has required fields (such as a localized `title`), providing *only* `externalReferenceCode` will fail with: `No value was provided for the language ID "en_US" in the required object field "title"`. To resolve this, include the required fields alongside the ERC:
    ```json
    "relationshipName": [
      {
        "externalReferenceCode": "REL-ERC-01",
        "title": "Related Item 1"
      },
      {
        "externalReferenceCode": "REL-ERC-02",
        "title": "Related Item 2"
      }
    ]
    ```
    Liferay matches and links the existing entry by `externalReferenceCode` while successfully passing payload schema validation.

- **Relationship Field (Direct Mapping)**: If mapping to a specific field (e.g., on an Account or System Object), use the `r_[relName]To[Target]_[targetIdField]` syntax.
  - **Using ID**: `38660` (value is a direct integer).
  - **Using ERC**: Not supported via the `r_...` field syntax; use the **Relationship Name** syntax above instead.

- **Dates**: Must use **ISO 8601** format with UTC 'Z' (e.g., `"2024-03-27T10:00:00Z"`).
- **Categorization**: Use `assetCategoryIds` (array of integers) or `assetTagNames` (array of strings) at the root of the item object (outside the `values` block) if `enableCategorization` is active.

### Headless CMS Folders & Media Assets (`CMSBasicDocument`)
When working with Liferay's new CMS UI (Files tab), raw attachments uploaded directly to custom objects are stored as internal Document Library attachments (folder `0`) and **do not appear in the CMS UI**. To make media visible in the CMS UI file tree:

#### 1. CMS Folder Creation (`ObjectEntryFolder`)
The root folder of the Files tab in every Space/Asset Library is **`L_FILES`** (system-created). Custom folders must be created as `ObjectEntryFolder` with `parentObjectEntryFolderExternalReferenceCode: "L_FILES"`:
```json
{
  "configuration": {
    "className": "com.liferay.headless.object.dto.v1_0.ObjectEntryFolder",
    "parameters": {
      "containsHeaders": "true",
      "createStrategy": "UPSERT",
      "onErrorFail": "false",
      "scopeKey": "YOUR-SPACE-ERC",
      "updateStrategy": "UPDATE"
    }
  },
  "items": [
    {
      "externalReferenceCode": "COURSES",
      "title": "Courses",
      "label": "Courses",
      "label_i18n": { "en_US": "Courses" },
      "parentObjectEntryFolderExternalReferenceCode": "L_FILES",
      "scopeKey": "YOUR-SPACE-ERC"
    }
  ]
}
```

#### 2. CMS Document Creation (`CMSBasicDocument`)
To register files so they appear in those CMS folders, import them as `CMSBasicDocument` entries:
- **`className`**: `com.liferay.object.rest.dto.v1_0.ObjectEntry`
- **`taskItemDelegateName`**: `CMSBasicDocument` (*Note: System objects do not use the `C_` prefix!*)
- **`objectEntryFolderExternalReferenceCode`**: The ERC of the target folder (e.g., `COURSES`).
```json
{
  "configuration": {
    "className": "com.liferay.object.rest.dto.v1_0.ObjectEntry",
    "parameters": {
      "containsHeaders": "true",
      "createStrategy": "UPSERT",
      "onErrorFail": "false",
      "scopeKey": "YOUR-SPACE-ERC",
      "taskItemDelegateName": "CMSBasicDocument",
      "updateStrategy": "UPDATE"
    },
    "taskItemDelegateName": "CMSBasicDocument"
  },
  "items": [
    {
      "externalReferenceCode": "CMS-DOC-COURSE-1-IMAGE",
      "title": "thumb_course_1.jpg",
      "title_i18n": { "en_US": "thumb_course_1.jpg" },
      "objectEntryFolderExternalReferenceCode": "COURSES",
      "scopeKey": "YOUR-SPACE-ERC",
      "file": {
        "externalReferenceCode": "FILE-COURSE-1-IMAGE",
        "name": "thumb_course_1.jpg",
        "fileBase64": "@batch_object_entry_file_base64@"
      }
    }
  ]
}
```

#### 3. Referencing CMS Files from Custom Objects
When an Object Definition field has `"fileSource": "CMSBasicDocument"`, reference the file in your custom object batch file using its `externalReferenceCode`:
```json
"representativeImage": {
  "name": "thumb_course_1.jpg",
  "externalReferenceCode": "FILE-COURSE-1-IMAGE"
}
```

```json
{
  "configuration": {
    "className": "com.liferay.object.rest.dto.v1_0.ObjectEntry",
    "parameters": {
      "taskItemDelegateName": "C_MyObject",
      "createStrategy": "UPSERT"
    }
  },
  "items": [
    {
      "externalReferenceCode": "ENTRY-001",
      "assetCategoryIds": [12345],
      "values": {
        "title": "Sample Entry 1",
        "r_accountToMyObject_accountEntryId": 38660,
        "timestamp": "2024-03-27T10:00:00Z"
      }
    }
  ]
}
```

## 3. Key Troubleshooting Lessons
1. **NPE during deployment**: Often caused by missing protocol (`http://`) in OAuth URLs or missing properties like `.serviceAddress`.
2. **Object not created**: Check if the `className` in the JSON `configuration` block exactly matches the REST DTO expected by the version of Liferay.
3. **Folder association**: Ensure the `externalReferenceCode` of the folder matches exactly what is provided in the object's `objectFolderExternalReferenceCode`.
4. **Site vs Company**: Site-scoped objects require a valid `scopeKey` (groupId) if the Batch Engine doesn't default correctly; `company` scope is more reliable for global definitions.
