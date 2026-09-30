# Liferay Migration Patterns

This document provides a collection of code patterns and implementations for various migration tasks within the Liferay ecosystem, including database migrations, Knowledge Base object movement, and workspace-specific implementations.

## 1. Database & Schema Migration

### MongoDB Migration Helper (TypeScript)
Used for managing migrations in systems utilizing MongoDB as a backend (e.g., Liferay Analytics or Phloem).

```typescript
import { Collection, Db } from 'mongodb';

export abstract class Migration {
	constructor(protected readonly db: Db) {}

	abstract up(): Promise<void>;

	protected getCollection(name: string): Collection {
		return this.db.collection(name);
	}
}

// Usage Example
export class CreateProjectCollection extends Migration {
	async up(): Promise<void> {
		await this.db.createCollection('Project');
		const collection = this.getCollection('Project');
		await collection.createIndex({ externalReferenceCode: 1 }, { unique: true });
	}
}
```

### Database Migration Importer (Java)
Experimental pattern for importing and mapping database structures.

```java
public class DBMigrationImport {
    public void migrate(Connection source, Connection target) {
        // Implementation for mapping tables and migrating data
    }
}
```

## 2. Content & Object Migration

### Moving Knowledge Base Objects
Implementation for transforming and moving Knowledge Base articles and folders.

```javascript
// KBDropdownPropsTransformer.js logic for moving objects
const moveKBObject = (id, targetFolderId) => {
    return Liferay.Util.fetch('/o/headless-delivery/v1.0/knowledge-base-articles/' + id, {
        method: 'PATCH',
        body: JSON.stringify({
            parentKnowledgeBaseFolderId: targetFolderId
        })
    });
};
```

## 3. Workspace Specific Implementations

### Liferay Customer Workspace (React)
Patterns for displaying and managing migrated data in the Customer Workspace.

**Ticket Attachments Table:**
```jsx
const TicketAttachmentsTable = ({ attachments }) => (
    <Table>
        <thead>
            <tr>
                <th>File Name</th>
                <th>Size</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            {attachments.map(a => (
                <tr key={a.id}>
                    <td>{a.name}</td>
                    <td>{a.size}</td>
                    <td><DownloadLink url={a.url} /></td>
                </tr>
            ))}
        </tbody>
    </Table>
);
```

**Team Members Table:**
```jsx
const TeamMembersTable = ({ members }) => (
    <Table>
        <thead>
            <tr>
                <th>Name</th>
                <th>Role</th>
            </tr>
        </thead>
        <tbody>
            {members.map(m => (
                <tr key={m.id}>
                    <td>{m.name}</td>
                    <td>{m.role}</td>
                </tr>
            ))}
        </tbody>
    </Table>
);
```

## 4. Documentation & Best Practices

- **Audience Targeting:** When migrating Audience Targeting data, ensure user segments and rules are mapped to the new Liferay Segments API.
- **Knowledge Base:** Verify that all attachments and nested folder structures are preserved during the transfer.
- **ERC Preservation:** Always prioritize preserving External Reference Codes (ERCs) during migration to maintain relational integrity across systems.
