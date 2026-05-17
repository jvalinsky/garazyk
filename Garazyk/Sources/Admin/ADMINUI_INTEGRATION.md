# AdminUI Integration Guide

This document explains how to integrate the new AdminUI with the existing PDSAdminHandler.

## Overview

The AdminUI is a modern, HTMX-based web interface for the PDS admin panel. It serves static assets
(HTML, CSS, JS) and renders partial HTML responses for dynamic content loading.

## Integration Steps

### 1. Import AdminUIHandler

Add to `PDSAdminHandler.m`:

```objc
#import "Admin/AdminUI/Handlers/AdminUIHandler.h"
```

### 2. Add AdminUI Routing

In `handleRequestPacketWithMethod:path:headers:body:`, add the following before the auth check:

```objc
// AdminUI static assets don't require authentication
if ([path hasPrefix:@"/admin/assets/"] || [path hasPrefix:@"/admin/css/"] || [path hasPrefix:@"/admin/js/"]) {
    AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
    NSInteger statusCode = 200;
    NSString *contentType = @"text/html";

    NSString *response = [uiHandler handleRequestWithMethod:method
                                                       path:path
                                                    headers:headers
                                                       body:body
                                                 statusCode:&statusCode
                                                contentType:&contentType];

    if (response) {
        return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
    }
}

// AdminUI entry point (serves index.html)
if ([path isEqualToString:@"/admin/ui"] || [path isEqualToString:@"/admin/ui/"]) {
    AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
    NSInteger statusCode = 200;
    NSString *contentType = @"text/html; charset=utf-8";

    NSString *response = [uiHandler handleRequestWithMethod:method
                                                       path:path
                                                    headers:headers
                                                       body:body
                                                 statusCode:&statusCode
                                                contentType:&contentType];

    if (response) {
        return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
    }
}
```

After the auth check, add:

```objc
// AdminUI partials require authentication
if ([path hasPrefix:@"/admin/partials/"]) {
    AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
    NSInteger statusCode = 200;
    NSString *contentType = @"text/html";

    NSString *response = [uiHandler handleRequestWithMethod:method
                                                       path:path
                                                    headers:headers
                                                       body:body
                                                 statusCode:&statusCode
                                                contentType:&contentType];

    if (response) {
        return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
    }
}
```

### 3. Add Response Helper Methods

Add these helper methods to `PDSAdminHandler`:

```objc
- (NSDictionary *)htmlResponseWithStatus:(NSInteger)status
                             contentType:(NSString *)contentType
                                   body:(NSString *)body {
    return @{
        @"status": @(status),
        @"contentType": contentType,
        @"body": body ?: @""
    };
}

- (NSDictionary *)jsonResponseWithStatus:(NSInteger)status body:(NSDictionary *)body {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body ?: @{}
                                                       options:0
                                                         error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    return @{
        @"status": @(status),
        @"contentType": @"application/json",
        @"body": jsonString ?: @"{}"
    };
}
```

## Routing Map

The AdminUI handles the following routes:

### Static Assets

- `/admin/assets/css/*` → CSS files
- `/admin/assets/js/*` → JavaScript files
- `/admin/assets/index.html` → Main UI entry point

### Partials (HTMX Responses)

- `/admin/partials/users` → Users section
- `/admin/partials/users/search` → User search results
- `/admin/partials/invites` → Invites section
- `/admin/partials/identity` → Identity management
- `/admin/partials/health` → Health dashboard
- `/admin/partials/health/status` → Health stats

### Entry Points

- `/admin/ui` → Full AdminUI application
- `/admin/ui/` → Full AdminUI application (with trailing slash)

## Asset Serving

AdminUIHandler serves assets from the bundle at runtime. The file structure must be:

```
Garazyk/Sources/Admin/AdminUI/
├── Assets/
│   ├── index.html
│   ├── css/
│   │   ├── system.css
│   │   ├── layout.css
│   │   ├── components.css
│   │   └── utilities.css
│   └── js/
│       └── app.js
└── Templates/
    ├── sections/
    │   ├── pds/*.html
    │   ├── plc/*.html
    │   ├── relay/*.html
    │   └── appview/*.html
    └── partials/
        ├── _user-row.html
        ├── _invite-row.html
        └── *.html
```

## Content-Type Mapping

AdminUIHandler automatically maps file extensions to content types:

- `.html` → `text/html; charset=utf-8`
- `.css` → `text/css`
- `.js` → `application/javascript`
- `.json` → `application/json`
- `.svg` → `image/svg+xml`
- `.png` → `image/png`
- `.jpg/.jpeg` → `image/jpeg`
- `.gif` → `image/gif`
- `.webp` → `image/webp`

## Authentication

- **Static assets** (/admin/assets/*): No authentication required
- **UI entry point** (/admin/ui): No authentication required (HTMX requests are authenticated
  separately)
- **Partials** (/admin/partials/*): Authentication required via PDSAdminAuth

The AdminUI entry point serves the full HTML shell with HTMX script. HTMX requests to
`/admin/partials/*` automatically include authentication headers and are validated by PDSAdminAuth.

## Testing

To test the integration:

1. Start the PDS server
2. Navigate to `http://localhost:8080/admin/ui`
3. Verify the UI loads with CSS and JavaScript
4. Click sidebar items to load partials
5. Verify service switching works (PDS/PLC/Relay/AppView/Chat tabs)

## Backward Compatibility

The existing JSON API endpoints remain unchanged:

- `/admin/users` (JSON)
- `/admin/invites` (JSON)
- `/admin/blobs` (JSON)
- `/admin/health` (JSON)
- `/admin/metrics` (JSON)

The new AdminUI coexists with these endpoints and provides an alternative HTML-based interface.

## Future Enhancements

1. **Dynamic data binding** - Connect HTMX responses to actual database queries
2. **Real-time updates** - Implement Server-Sent Events (SSE) for live data
3. **Form submissions** - Wire form handlers to admin service methods
4. **Error handling** - Display server errors in UI alerts
5. **Search functionality** - Implement full-text search for users, invites, etc.
