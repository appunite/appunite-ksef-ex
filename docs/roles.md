# Role Permission Matrix

## Roles

| Role | Description |
|---|---|
| **Owner** | Full access including destructive operations (delete company, transfer ownership) |
| **Admin** | Same as owner except cannot delete company or transfer ownership |
| **Reviewer** | Can view and manage expense invoices, trigger syncs |
| **Accountant** | Read-only invoice access plus exports and API token management |

## Permission Matrix

| Permission | Owner | Admin | Reviewer | Accountant |
|---|---|---|---|---|
| **Menu: Dashboard** | Y | Y | Y | Y |
| **Menu: Invoices** | Y | Y | Y (expense only) | Y (read-only) |
| **Menu: Syncs** | Y | Y | Y | - |
| **Menu: Categories** | Y | Y | - | - |
| **Menu: Tags** | Y | Y | - | - |
| **Menu: Exports** | Y | Y | - | Y |
| **Menu: Companies** | Y | Y | - | - |
| **Menu: Certificates** | Y | Y | - | - |
| **Menu: API Tokens** | Y | Y | - | Y |
| **Menu: Team** | Y | Y | - | - |
| Create/edit company | Y | Y | - | - |
| Delete company | Y | - | - | - |
| Transfer ownership | Y | - | - | - |
| Manage certificates | Y | Y | - | - |
| Manage team/invitations | Y | Y | - | - |
| Create/delete API tokens | Y | Y | - | Y |
| **Read** categories/tags | Y | Y | Y | Y |
| **Create/edit/delete** categories/tags | Y | Y | - | - |
| Add invoices (upload/create) | Y | Y | Y | - |
| Update invoice | Y | Y | Y | - |
| Assign tags/categories on invoice | Y | Y | Y | - |
| Approve/reject invoices | Y | Y | Y | - |
| View invoices | Y (all) | Y (all) | Y (expense only) | Y (all, read-only) |
| Create/download exports | Y | Y | - | Y |
| View syncs | Y | Y | Y | - |
| Trigger sync | Y | Y | Y | - |

## Implementation

All permission checks are centralized in `KsefHub.Authorization.can?(role, permission)`.

See `lib/ksef_hub/authorization.ex` for the full implementation.
