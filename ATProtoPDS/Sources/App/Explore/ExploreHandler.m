#import "App/Explore/ExploreHandler.h"
#import "App/Explore/ExploreCache.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

#pragma mark - API Endpoint Descriptor Classes

@implementation APIParameterDescriptor

+ (instancetype)initWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required {
    APIParameterDescriptor *param = [[APIParameterDescriptor alloc] init];
    param.name = name;
    param.in = inLocation;
    param.type = type;
    param.paramDescription = description;
    param.required = required;
    param.deprecated = NO;
    return param;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"name"] = self.name;
    dict[@"in"] = self.in;
    NSMutableDictionary *schema = [NSMutableDictionary dictionary];
    schema[@"type"] = self.type;
    if (self.paramDescription.length > 0) {
        schema[@"description"] = self.paramDescription;
    }
    dict[@"schema"] = schema;
    dict[@"required"] = self.required ? @YES : @NO;
    if (self.deprecated) {
        dict[@"deprecated"] = @YES;
    }
    return [dict copy];
}

@end

@implementation APIResponseDescriptor

+ (instancetype)initWithStatusCode:(NSString *)statusCode description:(NSString *)description {
    APIResponseDescriptor *resp = [[APIResponseDescriptor alloc] init];
    resp.statusCode = statusCode;
    resp.responseDescription = description;
    return resp;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"description"] = self.responseDescription;

    if (self.schemaRef.length > 0 || self.arrayItemRef.length > 0) {
        NSMutableDictionary *content = [NSMutableDictionary dictionary];
        NSMutableDictionary *mediaType = [NSMutableDictionary dictionary];

        if (self.arrayItemRef.length > 0) {
            mediaType[@"schema"] = @{
                @"type": @"array",
                @"items": @{@"$ref": self.arrayItemRef}
            };
        } else if (self.schemaRef.length > 0) {
            mediaType[@"schema"] = @{@"$ref": self.schemaRef};
        }

        content[@"application/json"] = mediaType;
        dict[@"content"] = content;
    }

    return [dict copy];
}

@end

@implementation APIEndpointDescriptor

+ (instancetype)descriptorWithPath:(NSString *)path
                            method:(NSString *)method
                           summary:(NSString *)summary
                      endpointName:(NSString *)endpointName
                      operationId:(NSString *)operationId
                             tags:(NSArray<NSString *> *)tags
                        parameters:(NSArray<APIParameterDescriptor *> *)parameters
                        responses:(NSArray<APIResponseDescriptor *> *)responses {
    APIEndpointDescriptor *desc = [[APIEndpointDescriptor alloc] init];
    desc.path = path;
    desc.method = method;
    desc.summary = summary;
    desc.endpointName = endpointName;
    desc.operationId = operationId;
    desc.tags = tags;
    desc.parameters = parameters ?: @[];
    desc.responses = responses ?: @[];
    return desc;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    if (self.operationId.length > 0) {
        dict[@"operationId"] = self.operationId;
    }
    if (self.summary.length > 0) {
        dict[@"summary"] = self.summary;
    }
    if (self.endpointDescription.length > 0) {
        dict[@"description"] = self.endpointDescription;
    }
    if (self.tags.count > 0) {
        dict[@"tags"] = self.tags;
    }
    if (self.deprecated) {
        dict[@"deprecated"] = @YES;
    }

    if (self.parameters.count > 0) {
        NSMutableArray *paramDicts = [NSMutableArray array];
        for (APIParameterDescriptor *param in self.parameters) {
            [paramDicts addObject:[param openAPIDict]];
        }
        dict[@"parameters"] = paramDicts;
    }

    if (self.responses.count > 0) {
        NSMutableDictionary *responses = [NSMutableDictionary dictionary];
        for (APIResponseDescriptor *resp in self.responses) {
            responses[resp.statusCode] = [resp openAPIDict];
        }
        dict[@"responses"] = responses;
    }

    return [dict copy];
}

@end

#pragma mark - ExploreHandler

@interface ExploreHandler ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *plcServerURL;
@property (nonatomic, assign) NSTimeInterval didTTL;
@property (nonatomic, assign) NSTimeInterval plcTTL;
@property (nonatomic, assign) NSTimeInterval accountTTL;
@property (nonatomic, strong) ExploreCache *cache;
@property (nonatomic, weak) PDSController *controller;
@end

@implementation ExploreHandler

+ (instancetype)sharedHandler {
    static ExploreHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ExploreHandler alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [ExploreCache sharedCache];
        _enabled = YES;
        _cacheDirectory = @"/tmp/pds-explore-cache";
        _plcServerURL = @"https://plc.directory";
        _didTTL = 3600;
        _plcTTL = 86400;
        _accountTTL = 300;
        [self loadConfiguration];
    }
    return self;
}

- (void)setController:(PDSController *)controller {
    _controller = controller;
}

- (void)loadConfiguration {
    NSString *configPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"yaml"];
    if (!configPath) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        configPath = [[appSupport stringByAppendingPathComponent:@"ATProtoPDS"] stringByAppendingPathComponent:@"config.yaml"];
    }
    
    if (configPath) {
        NSString *content = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
        if (content) {
            [self parseConfig:content];
        }
    }
}

- (void)parseConfig:(NSString *)content {
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    BOOL inExploreSection = NO;
    
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([trimmed hasPrefix:@"explore:"]) {
            inExploreSection = YES;
            continue;
        }
        
        if (inExploreSection && [trimmed hasPrefix:@"#"]) {
            continue;
        }
        
        if (inExploreSection && trimmed.length > 0 && ![trimmed hasPrefix:@"  "] && ![trimmed hasPrefix:@"\t"]) {
            inExploreSection = NO;
        }
        
        if (!inExploreSection) continue;
        
        if ([trimmed containsString:@"enabled:"]) {
            self.enabled = [[[trimmed componentsSeparatedByString:@":"] lastObject] 
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].boolValue;
        }
        else if ([trimmed containsString:@"plc_server:"]) {
            self.plcServerURL = [[[trimmed componentsSeparatedByString:@":"] lastObject]
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        else if ([trimmed containsString:@"cache_directory:"]) {
            NSString *value = [[[trimmed componentsSeparatedByString:@":"] lastObject]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            self.cacheDirectory = [value stringByExpandingTildeInPath];
        }
        else if ([trimmed containsString:@"did_ttl_seconds:"]) {
            self.didTTL = [[[trimmed componentsSeparatedByString:@":"] lastObject]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].doubleValue;
        }
        else if ([trimmed containsString:@"plc_log_ttl_seconds:"]) {
            self.plcTTL = [[[trimmed componentsSeparatedByString:@":"] lastObject]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].doubleValue;
        }
        else if ([trimmed containsString:@"account_list_ttl_seconds:"]) {
            self.accountTTL = [[[trimmed componentsSeparatedByString:@":"] lastObject]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].doubleValue;
        }
    }
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
    if (!self.enabled) return NO;
    return [request.path hasPrefix:@"/explore"];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    NSLog(@"ExploreHandler handleRequest: %@", path);
    
    if ([path isEqualToString:@"/explore/"] || [path isEqualToString:@"/explore"]) {
        [self serveIndex:response];
    }
    else if ([path hasPrefix:@"/explore/css/"]) {
        [self serveCss:request response:response];
    }
    else if ([path hasPrefix:@"/explore/js/"]) {
        [self serveJs:request response:response];
    }
    else if ([path hasPrefix:@"/explore/api/"]) {
        [self handleApiRequest:request response:response];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Not Found", @"path": path}];
    }
}

#pragma mark - Static Files

- (void)serveIndex:(HttpResponse *)response {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *indexPath = [cwd stringByAppendingPathComponent:@"ATProtoPDS/Sources/App/Explore/Assets/index.html"];

    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:indexPath encoding:NSUTF8StringEncoding error:&error];

    if (error || !html) {
        // Fallback to old HTML if file not found
        NSString *fallbackHtml = @"<!DOCTYPE html>"
        "<html lang=\"en\">"
        "<head>"
        "    <meta charset=\"UTF-8\">"
        "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        "    <title>ATProto PDS Explorer</title>"
        "</head>"
        "<body>"
        "    <h1>ATProto PDS Explorer</h1>"
        "    <p>Error: Could not load index.html</p>"
        "</body>"
        "</html>";
        html = fallbackHtml;
    }

    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)serveCss:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *css = @"body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; }"
    ".sidebar { position: fixed; left: 0; top: 0; width: 250px; height: 100vh; background: #f8f9fa; border-right: 1px solid #dee2e6; padding: 20px; }"
    ".sidebar h1 { margin-bottom: 20px; font-size: 18px; }"
    ".sidebar ul { list-style: none; padding: 0; }"
    ".sidebar li { margin-bottom: 10px; }"
    ".sidebar a { text-decoration: none; color: #007bff; display: block; padding: 8px; border-radius: 4px; }"
    ".sidebar a:hover { background: #e9ecef; }"
    ".content { margin-left: 250px; padding: 20px; }"
    "h2 { color: #333; margin-bottom: 20px; }"
    "p { color: #666; }"
    ".accounts, .records, .repos, .did { display: none; }"
    ".accounts.show, .records.show, .repos.show, .did.show { display: block; }"
    "table { width: 100%; border-collapse: collapse; margin-top: 20px; }"
    "th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }"
    "th { background-color: #f8f9fa; font-weight: bold; }"
    ".json { font-family: monospace; background: #f8f9fa; padding: 10px; border-radius: 4px; white-space: pre-wrap; }";

    response.statusCode = 200;
    response.contentType = @"text/css; charset=utf-8";
    [response setBody:[css dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)serveJs:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *js = @"function showAccounts() { hideAll(); document.querySelector('.accounts').classList.add('show'); loadAccounts(); }"
    "async function showRecords() { hideAll(); document.querySelector('.records').classList.add('show'); loadRecords(); }"
    "async function showRepos() { hideAll(); document.querySelector('.repos').classList.add('show'); loadRepositories(); }"
    "function showDID() { hideAll(); document.querySelector('.did').classList.add('show'); loadDID(); }"
    "function hideAll() {"
    "  document.querySelectorAll('.accounts, .records, .repos, .did').forEach(el => el.classList.remove('show'));"
    "}"
    "async function loadAccounts() {"
    "  try {"
    "    const response = await fetch('/explore/api/accounts');"
    "    const data = await response.json();"
    "    const container = document.querySelector('.accounts');"
    "    "
    "    if (data.accounts && data.accounts.length > 0) {"
    "      let html = '<h3>Accounts (' + data.count + ')</h3>';"
    "      html += '<table>';"
    "      html += '<tr><th>DID</th><th>Handle</th><th>Email</th><th>Created</th><th>Updated</th></tr>';"
    "      "
    "      data.accounts.forEach(account => {"
    "        const createdDate = new Date(account.createdAt * 1000).toLocaleString();"
    "        const updatedDate = new Date(account.updatedAt * 1000).toLocaleString();"
    "        html += '<tr>';"
    "        html += '<td><code>' + (account.did || '') + '</code></td>';"
    "        html += '<td>' + (account.handle || '') + '</td>';"
    "        html += '<td>' + (account.email || 'N/A') + '</td>';"
    "        html += '<td>' + createdDate + '</td>';"
    "        html += '<td>' + updatedDate + '</td>';"
    "        html += '</tr>';"
    "      });"
    "      "
    "      html += '</table>';"
    "      container.innerHTML = html;"
    "    } else {"
    "      container.innerHTML = '<h3>Accounts</h3><p>No accounts found in the database.</p><p><small>Use the setup script to create test accounts first.</small></p>';"
    "    }"
    "  } catch (e) {"
    "    document.querySelector('.accounts').innerHTML = '<h3>Error loading accounts</h3><p>' + e.message + '</p>';"
    "  }"
    "}"
    "async function loadRecords() {"
    "  try {"
    "    const container = document.querySelector('.records');"
    "    container.innerHTML = '<h3>Records</h3><p>Loading records...</p>';"
    "    "
        "    // For now, show a simple interface to query records"
    "    let html = '<h3>Records</h3>';"
    "    html += '<h4>Create Record</h4>';"
    "    html += '<div class=\"record-create\" style=\"margin-bottom: 20px; padding: 15px; background: #f5f5f5; border-radius: 4px;\">';"
    "    html += '<label>DID: <input type=\"text\" id=\"create-did\" placeholder=\"did:plc:...\" style=\"width: 350px;\"></label><br>';"
    "    html += '<label>Collection: <input type=\"text\" id=\"create-collection\" placeholder=\"app.bsky.feed.post\" style=\"width: 350px;\"></label><br>';"
    "    html += '<label>RKey: <input type=\"text\" id=\"create-rkey\" placeholder=\"e.g., test1\" style=\"width: 350px;\"></label><br>';"
    "    html += '<label>Value (JSON): <textarea id=\"create-value\" placeholder=\"{...}\" style=\"width: 350px; height: 80px;\"></textarea></label><br>';"
    "    html += '<button onclick=\"createRecord()\" style=\"margin-top: 10px;\">Create Record</button>';"
    "    html += '</div>';"
    "    html += '<div id=\"create-result\"></div>';"
    "    html += '<h4>Query Records</h4>';"
    "    html += '<div class=\"record-query\">';"
    "    html += '<label>DID: <input type=\"text\" id=\"record-did\" placeholder=\"did:plc:...\" style=\"width: 300px;\"></label><br>';"
    "    html += '<label>Collection: <input type=\"text\" id=\"record-collection\" placeholder=\"app.bsky.feed.post\" style=\"width: 300px;\"></label><br>';"
    "    html += '<button onclick=\"queryRecords()\">Query Records</button>';"
    "    html += '</div>';"
    "    html += '<div id=\"records-result\"></div>';"
    "    container.innerHTML = html;"
    "  } catch (e) {"
    "    document.querySelector('.records').innerHTML = '<h3>Error loading records</h3><p>' + e.message + '</p>';"
        "  }"
    "}"
    "async function createRecord() {"
    "  const did = document.getElementById('create-did').value;"
    "  const collection = document.getElementById('create-collection').value;"
    "  const rkey = document.getElementById('create-rkey').value;"
    "  const value = document.getElementById('create-value').value;"
    "  const resultDiv = document.getElementById('create-result');"
    "  "
    "  if (!did || !collection || !rkey || !value) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Please fill in all fields</p>';"
    "    return;"
    "  }"
    "  "
    "  try {"
    "    resultDiv.innerHTML = '<p>Creating record...</p>';"
    "    const params = new URLSearchParams({"
    "      did: did,"
    "      collection: collection,"
    "      rkey: rkey,"
    "      value: value"
    "    });"
    "    const response = await fetch('/explore/api/create-record?' + params.toString(), { method: 'POST' });"
    "    const data = await response.json();"
    "    "
    "    if (data.error) {"
    "      resultDiv.innerHTML = '<p style=\"color: red;\">Error: ' + data.error + '</p>';"
    "    } else {"
    "      let html = '<p style=\"color: green;\">Record created!</p>';"
    "      html += '<pre class=\"json\">' + JSON.stringify(data, null, 2) + '</pre>';"
    "      resultDiv.innerHTML = html;"
    "    }"
    "  } catch (e) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Error: ' + e.message + '</p>';"
    "  }"
    "}"
    "async function loadRepositories() {"
    "  try {"
    "    const container = document.querySelector('.repos');"
    "    container.innerHTML = '<h3>Repositories</h3><p>Loading repositories...</p>';"
    "    "
    "    // For now, show account repos"
    "    const response = await fetch('/explore/api/accounts');"
    "    const data = await response.json();"
    "    "
    "    if (data.accounts && data.accounts.length > 0) {"
    "      let html = '<h3>Repositories (' + data.count + ')</h3>';"
    "      html += '<table>';"
    "      html += '<tr><th>DID</th><th>Handle</th><th>Repository Status</th><th>Actions</th></tr>';"
    "      "
    "      data.accounts.forEach(account => {"
    "        html += '<tr>';"
    "        html += '<td><code>' + (account.did || '') + '</code></td>';"
    "        html += '<td>' + (account.handle || '') + '</td>';"
    "        html += '<td>Active</td>';"
    "        html += '<td><button onclick=\"describeRepo(\'' + account.did + '\')\">Describe</button></td>';"
    "        html += '</tr>';"
    "      });"
    "      "
    "      html += '</table>';"
    "      html += '<div id=\"repo-details\"></div>';"
    "      container.innerHTML = html;"
    "    } else {"
    "      container.innerHTML = '<h3>Repositories</h3><p>No accounts found.</p>';"
    "    }"
    "  } catch (e) {"
    "    document.querySelector('.repos').innerHTML = '<h3>Error loading repositories</h3><p>' + e.message + '</p>';"
    "  }"
    "}"
    "async function loadDID() {"
    "  try {"
    "    const container = document.querySelector('.did');"
    "    container.innerHTML = '<h3>DID Resolution</h3><p>Loading...</p>';"
    "    "
    "    let html = '<h3>DID Resolution</h3>';"
    "    html += '<div class=\"did-query\">';"
    "    html += '<label>DID: <input type=\"text\" id=\"resolve-did\" placeholder=\"did:plc:...\" style=\"width: 400px;\"></label><br>';"
    "    html += '<button onclick=\"resolveDID()\">Resolve DID</button>';"
    "    html += '</div>';"
    "    html += '<div id=\"did-result\"></div>';"
    "    container.innerHTML = html;"
    "  } catch (e) {"
    "    document.querySelector('.did').innerHTML = '<h3>Error loading DID interface</h3><p>' + e.message + '</p>';"
    "  }"
    "}"
    "async function resolveDID() {"
    "  const did = document.getElementById('resolve-did').value;"
    "  const resultDiv = document.getElementById('did-result');"
    "  "
    "  if (!did) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Please enter a DID</p>';"
    "    return;"
    "  }"
    "  "
    "  try {"
    "    resultDiv.innerHTML = '<p>Resolving DID...</p>';"
    "    const response = await fetch('/explore/api/did?did=' + encodeURIComponent(did));"
    "    "
    "    const contentType = response.headers.get('content-type');"
    "    if (contentType && contentType.includes('application/json')) {"
    "      const data = await response.json();"
    "      if (data.error) {"
    "        resultDiv.innerHTML = '<p style=\"color: red;\">Error: ' + data.error + '</p>';"
    "      } else {"
    "        let html = '<h4>DID Document</h4>';"
    "        html += '<pre class=\"json\">' + JSON.stringify(data, null, 2) + '</pre>';"
    "        resultDiv.innerHTML = html;"
    "      }"
    "    } else {"
    "      const text = await response.text();"
    "      let html = '<h4>DID Document</h4>';"
    "      html += '<pre class=\"json\">' + text + '</pre>';"
    "      resultDiv.innerHTML = html;"
    "    }"
    "  } catch (e) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Error: ' + e.message + '</p>';"
    "  }"
    "}"
    "async function queryRecords() {"
    "  const did = document.getElementById('record-did').value;"
    "  const collection = document.getElementById('record-collection').value;"
    "  const resultDiv = document.getElementById('records-result');"
    "  "
    "  if (!did || !collection) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Please enter both DID and Collection</p>';"
    "    return;"
    "  }"
    "  "
    "  try {"
    "    resultDiv.innerHTML = '<p>Loading records...</p>';"
    "    const response = await fetch('/explore/api/account-records?did=' + encodeURIComponent(did) + '&collection=' + encodeURIComponent(collection));"
    "    const data = await response.json();"
    "    "
    "    if (data.records && data.records.length > 0) {"
    "      let html = '<h4>Records (' + data.records.length + ')</h4>';"
    "      html += '<table>';"
    "      html += '<tr><th>URI</th><th>CID</th><th>Actions</th></tr>';"
    "      "
    "      data.records.forEach(record => {"
    "        html += '<tr>';"
    "        html += '<td><code>' + (record.uri || '') + '</code></td>';"
    "        html += '<td><code>' + (record.cid || '') + '</code></td>';"
    "        html += '<td><button onclick=\"viewRecord(\'' + record.uri + '\')\">View</button></td>';"
    "        html += '</tr>';"
    "      });"
    "      "
    "      html += '</table>';"
    "      resultDiv.innerHTML = html;"
    "    } else {"
    "      resultDiv.innerHTML = '<p>No records found for this collection.</p>';"
    "    }"
    "  } catch (e) {"
    "    resultDiv.innerHTML = '<p style=\"color: red;\">Error: ' + e.message + '</p>';"
    "  }"
    "}"
    "async function describeRepo(did) {"
    "  const detailsDiv = document.getElementById('repo-details');"
    "  try {"
    "    detailsDiv.innerHTML = '<p>Loading repository details...</p>';"
    "    const response = await fetch('/explore/api/describe?did=' + encodeURIComponent(did));"
    "    const data = await response.json();"
    "    "
    "    let html = '<h4>Repository: ' + did + '</h4>';"
    "    html += '<pre class=\"json\">' + JSON.stringify(data, null, 2) + '</pre>';"
    "    detailsDiv.innerHTML = html;"
    "  } catch (e) {"
    "    detailsDiv.innerHTML = '<p style=\"color: red;\">Error loading repository details: ' + e.message + '</p>';"
    "  }"
    "}"
    "async function viewRecord(uri) {"
    "  try {"
    "    const response = await fetch('/explore/api/record?uri=' + encodeURIComponent(uri));"
    "    const data = await response.json();"
    "    "
    "    const modal = document.createElement('div');"
    "    modal.style.cssText = 'position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000;';"
    "    modal.innerHTML = '<div style=\"position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 20px; max-width: 80%; max-height: 80%; overflow: auto;\">"
    "      + '<h3>Record: ' + uri + '</h3>'"
    "      + '<pre style=\"white-space: pre-wrap;\">' + JSON.stringify(data, null, 2) + '</pre>'"
    "      + '<button onclick=\"this.parentElement.parentElement.remove()\" style=\"margin-top: 10px;\">Close</button>'"
    "      + '</div>';"
    "    document.body.appendChild(modal);"
    "  } catch (e) {"
    "    alert('Error loading record: ' + e.message);"
    "  }"
    "}"
    "document.addEventListener('DOMContentLoaded', function() {"
    "  document.querySelectorAll('.sidebar a').forEach(link => {"
    "    link.addEventListener('click', function(e) {"
    "      e.preventDefault();"
    "      document.querySelectorAll('.sidebar a').forEach(a => a.classList.remove('active'));"
    "      this.classList.add('active');"
    "    });"
    "  });"
    "});";

    response.statusCode = 200;
    response.contentType = @"application/javascript; charset=utf-8";
    [response setBody:[js dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - API Endpoints

- (void)handleApiRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *endpoint = [self apiEndpointForPath:request.path];
    NSString *query = request.queryString ?: @"";
    NSDictionary *params = [self parseQueryString:query];

    NSLog(@"handleApiRequest: path=%@, endpoint=%@", request.path, endpoint);
    
    response.statusCode = 200;
    response.contentType = @"application/json; charset=utf-8";
    
    if ([endpoint isEqualToString:@"lookup"]) {
        [self handleApiLookup:params response:response];
    }
    else if ([endpoint isEqualToString:@"did"]) {
        [self handleApiDid:params response:response];
    }
    else if ([endpoint isEqualToString:@"plc-log"]) {
        [self handleApiPlcLog:params response:response];
    }
    else if ([endpoint isEqualToString:@"accounts"]) {
        [self handleApiAccounts:params response:response];
    }
    else if ([endpoint isEqualToString:@"describe"]) {
        [self handleApiDescribe:params response:response];
    }
    else if ([endpoint isEqualToString:@"records"]) {
        [self handleApiRecords:params response:response];
    }
    else if ([endpoint isEqualToString:@"record"]) {
        [self handleApiRecord:params response:response];
    }
    else if ([endpoint isEqualToString:@"blob"]) {
        [self handleApiBlob:params response:response];
    }
    else if ([endpoint isEqualToString:@"cid-decode"]) {
        [self handleApiCidDecode:params response:response];
    }
    else if ([endpoint isEqualToString:@"repositories"]) {
        [self handleApiRepositories:params response:response];
    }
    else if ([endpoint isEqualToString:@"collections"]) {
        [self handleApiCollections:params response:response];
    }
    else if ([endpoint isEqualToString:@"did"]) {
        [self handleApiDidResolve:params response:response];
    }
    else if ([endpoint isEqualToString:@"account-details"]) {
        [self handleApiAccountDetails:params response:response];
    }
    else if ([endpoint isEqualToString:@"account-records"]) {
        [self handleApiAccountRecords:params response:response];
    }
    else if ([endpoint isEqualToString:@"record-details"]) {
        [self handleApiRecordDetails:params response:response];
    }
    else if ([endpoint isEqualToString:@"cid-info"]) {
        [self handleApiCidInfo:params response:response];
    }
    else if ([endpoint isEqualToString:@"create-record"]) {
        [self handleApiCreateRecord:params response:response];
    }
    else if ([endpoint isEqualToString:@"debug-paths"]) {
        // Debug endpoint to check paths
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString *dbPath = [cwd stringByAppendingPathComponent:@"data/pds.db"];
        BOOL dbExists = [[NSFileManager defaultManager] fileExistsAtPath:dbPath];
        [response setJsonBody:@{
            @"cwd": cwd ?: @"",
            @"dbPath": dbPath ?: @"",
            @"dbExists": @(dbExists)
        }];
    }
    else if ([endpoint isEqualToString:@"docs"]) {
        [self handleApiDocs:params response:response];
    }
    else if ([endpoint isEqualToString:@"openapi.yaml"] || [endpoint isEqualToString:@"openapi.json"]) {
        NSLog(@"[ExploreHandler] OpenAPI spec request received");
        [self handleApiOpenapiSpec:params response:response];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Unknown endpoint", @"endpoint": endpoint}];
    }
}

- (NSString *)apiEndpointForPath:(NSString *)path {
    NSArray *parts = [[path substringFromIndex:[@"/explore/api/" length]] componentsSeparatedByString:@"/"];
    return parts.firstObject ?: @"";
}

- (sqlite3 *)openDatabaseWithError:(NSString **)errorMessage {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *dbPath = [cwd stringByAppendingPathComponent:@"data/pds.db"];

    sqlite3 *db = NULL;
    int rc = sqlite3_open(dbPath.fileSystemRepresentation, &db);
    if (rc != SQLITE_OK) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Failed to open database: %s", sqlite3_errmsg(db)];
        return NULL;
    }

    // Add value column if it doesn't exist (migration)
    char *errMsg = NULL;
    int migrationRc = sqlite3_exec(db, "ALTER TABLE records ADD COLUMN value TEXT", NULL, NULL, &errMsg);
    if (errMsg) {
        sqlite3_free(errMsg);
        errMsg = NULL;
    }

    return db;
}

- (void)handleApiRepositories:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{
            @"repositories": @[],
            @"error": errorMessage ?: @"Failed to open database"
        }];
        return;
    }

    // Force WAL checkpoint
    sqlite3_wal_checkpoint(db, NULL);

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT did, handle, email, created_at, updated_at FROM accounts ORDER BY created_at DESC LIMIT 1000", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"repositories": @[],
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    NSMutableArray *accountData = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *did = sqlite3_column_text(stmt, 0);
        const unsigned char *handle = sqlite3_column_text(stmt, 1);
        const unsigned char *email = sqlite3_column_text(stmt, 2);

        [accountData addObject:@{
            @"did": did ? @((const char *)did) : @"",
            @"handle": handle ? @((const char *)handle) : @"",
            @"email": email ? @((const char *)email) : @"",
            @"createdAt": @(sqlite3_column_int64(stmt, 3)),
            @"updatedAt": @(sqlite3_column_int64(stmt, 4))
        }];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    [response setJsonBody:@{
        @"repositories": accountData,
        @"count": @(accountData.count)
    }];
}

- (void)handleApiDidResolve:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    // Try to resolve DID using our cache/API
    NSString *cached = [self.cache getDidDocument:did];
    if (cached) {
        [response setBody:[cached dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    NSString *doc = [self fetchDidDocument:did];
    if (doc) {
        [self.cache setDidDocument:did value:doc];
        [response setBody:[doc dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to resolve DID", @"did": did}];
    }
}

- (void)handleApiCreateRecord:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *collection = params[@"collection"];
    NSString *rkey = params[@"rkey"];
    NSString *valueJson = params[@"value"];

    if (!did || !collection || !rkey || !valueJson) {
        [response setJsonBody:@{
            @"error": @"Missing required parameters",
            @"required": @[@"did", @"collection", @"rkey", @"value"]
        }];
        return;
    }

    NSError *jsonError = nil;
    NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:&jsonError];

    if (!value || jsonError) {
        [response setJsonBody:@{
            @"error": @"Invalid JSON in value parameter",
            @"details": jsonError.localizedDescription ?: @"Unknown error"
        }];
        return;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    NSString *cid = [self generateCIDForValue:value];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Failed to generate CID for value"}];
        return;
    }

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    NSString *createdAt = [[NSDate date] description];
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, created_at, value) VALUES (?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, collection.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, rkey.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, cid.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, createdAt.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 7, valueJson.UTF8String, -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        [response setJsonBody:@{
            @"error": @"Failed to insert record",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_close(db);

    [response setJsonBody:@{
        @"uri": uri,
        @"did": did,
        @"collection": collection,
        @"rkey": rkey,
        @"cid": cid,
        @"value": value,
        @"createdAt": createdAt
    }];
}

- (NSString *)generateCIDForValue:(NSDictionary *)value {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!jsonData) return nil;

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, hash);

    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:(uint8_t[]){0x12, 0x20} length:2];
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    NSMutableData *cidData = [NSMutableData data];
    [cidData appendBytes:(uint8_t[]){0x01, 0x71} length:2];
    [cidData appendData:multihash];

    return [NSString stringWithFormat:@"b%@", [self base32Encode:cidData]];
}

- (NSString *)base32Encode:(NSData *)data {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];
    NSUInteger length = data.length;
    NSUInteger i = 0;

    while (i < length) {
        uint8_t byte = ((uint8_t *)data.bytes)[i++];
        [result appendFormat:@"%c", alphabet[byte >> 3]];
        uint8_t nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((byte & 0x07) << 2) | (nextByte >> 6)]];
        if (i >= length + 1) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 1) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((nextByte & 0x0F) << 1) | (nextByte >> 7)]];
        if (i >= length) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 2) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[nextByte & 0x1F]];
    }

    return result;
}

- (void)handleApiAccountDetails:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    // Get basic account info from our database
    NSError *error = nil;
    PDSDatabaseAccount *account = [self.controller.database getAccountByDid:did error:&error];

    if (!account) {
        [response setJsonBody:@{@"error": @"Account not found", @"did": did}];
        return;
    }

    NSDictionary *accountInfo = @{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"email": account.email ?: [NSNull null],
        @"createdAt": @(account.createdAt),
        @"updatedAt": @(account.updatedAt)
    };

    [response setJsonBody:accountInfo];
}

- (void)handleApiCollections:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT DISTINCT collection, COUNT(*) as count FROM records WHERE did = ? GROUP BY collection ORDER BY collection", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    NSMutableArray *collections = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *collection = (const char *)sqlite3_column_text(stmt, 0);
        int count = sqlite3_column_int(stmt, 1);

        [collections addObject:@{
            @"collection": collection ? @(collection) : @"",
            @"count": @(count)
        }];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    [response setJsonBody:@{
        @"did": did,
        @"collections": collections,
        @"count": @(collections.count)
    }];
}

- (void)handleApiDescribe:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    // Get collections with counts
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT collection, COUNT(*) as count FROM records WHERE did = ? GROUP BY collection ORDER BY collection", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);

    NSMutableArray *collections = [NSMutableArray array];
    int totalRecords = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *collection = (const char *)sqlite3_column_text(stmt, 0);
        int count = sqlite3_column_int(stmt, 1);

        [collections addObject:@{
            @"collection": collection ? @(collection) : @"",
            @"count": @(count)
        }];
        totalRecords += count;
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Get account info
    NSString *handle = @"";
    db = [self openDatabaseWithError:nil];
    if (db) {
        rc = sqlite3_prepare_v2(db, "SELECT handle FROM accounts WHERE did = ?", -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *h = (const char *)sqlite3_column_text(stmt, 0);
                handle = h ? @(h) : @"";
            }
        }
        sqlite3_finalize(stmt);
        sqlite3_close(db);
    }

    [response setJsonBody:@{
        @"did": did,
        @"handle": handle,
        @"collections": collections,
        @"recordCount": @(totalRecords),
        @"tree": @"MST (simulated)"
    }];
}

- (void)handleApiAccountRecords:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSString *collection = params[@"collection"];
    NSString *limitStr = params[@"limit"] ?: @"50";

    NSUInteger limit = [limitStr integerValue];
    if (limit > 200) limit = 200;

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    NSString *sql;
    sqlite3_stmt *stmt;
    int rc;

    if (collection && collection.length > 0) {
        sql = @"SELECT uri, did, collection, rkey, cid, created_at, value FROM records WHERE did = ? AND collection = ? ORDER BY created_at DESC LIMIT ?";
        rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, collection.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 3, limit);
        }
    } else {
        sql = @"SELECT uri, did, collection, rkey, cid, created_at, value FROM records WHERE did = ? ORDER BY created_at DESC LIMIT ?";
        rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
        if (rc == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, limit);
        }
    }

    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare query",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    NSMutableArray *recordArray = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *uri = (const char *)sqlite3_column_text(stmt, 0);
        const char *col = (const char *)sqlite3_column_text(stmt, 2);
        const char *rkey = (const char *)sqlite3_column_text(stmt, 3);
        const char *cid = (const char *)sqlite3_column_text(stmt, 4);
        const char *valueStr = (const char *)sqlite3_column_text(stmt, 6);

        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"uri"] = uri ? @(uri) : @"";
        record[@"did"] = did;
        record[@"collection"] = col ? @(col) : @"";
        record[@"rkey"] = rkey ? @(rkey) : @"";
        record[@"cid"] = cid ? @(cid) : @"";

        // Parse value JSON
        if (valueStr) {
            NSData *jsonData = [NSData dataWithBytes:valueStr length:strlen(valueStr)];
            NSError *parseError = nil;
            NSDictionary *parsedValue = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
            record[@"value"] = parsedValue ?: @{@"raw": @(valueStr)};
        } else {
            record[@"value"] = @{};
        }

        [recordArray addObject:record];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    [response setJsonBody:@{
        @"did": did,
        @"collection": collection ?: [NSNull null],
        @"records": recordArray,
        @"count": @(recordArray.count)
    }];
}

- (void)handleApiRecordDetails:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *uri = params[@"uri"];
    if (!uri) {
        [response setJsonBody:@{@"error": @"Missing uri parameter"}];
        return;
    }

    // Extract DID from URI
    NSArray *uriParts = [uri componentsSeparatedByString:@"/"];
    NSString *did = uriParts.count >= 3 ? uriParts[2] : nil;

    if (!did) {
        [response setJsonBody:@{@"error": @"Invalid URI format"}];
        return;
    }

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT uri, did, collection, rkey, cid, created_at, value FROM records WHERE uri = ?", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);

    NSDictionary *recordValue = @{};
    NSString *recordCid = @"";
    NSString *recordCollection = @"";
    NSString *recordRkey = @"";

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *cid = (const char *)sqlite3_column_text(stmt, 4);
        const char *col = (const char *)sqlite3_column_text(stmt, 2);
        const char *rkey = (const char *)sqlite3_column_text(stmt, 3);
        const char *valueStr = (const char *)sqlite3_column_text(stmt, 6);

        recordCid = cid ? @(cid) : @"";
        recordCollection = col ? @(col) : @"";
        recordRkey = rkey ? @(rkey) : @"";

        if (valueStr) {
            NSData *jsonData = [NSData dataWithBytes:valueStr length:strlen(valueStr)];
            NSError *parseError = nil;
            recordValue = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
            if (!recordValue) {
                recordValue = @{@"raw": @(valueStr)};
            }
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (recordCid.length == 0) {
        [response setJsonBody:@{@"error": @"Record not found", @"uri": uri}];
        return;
    }

    [response setJsonBody:@{
        @"uri": uri,
        @"did": did,
        @"cid": recordCid,
        @"collection": recordCollection,
        @"rkey": recordRkey,
        @"value": recordValue
    }];
}

- (void)handleApiCidInfo:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }

    NSDictionary *cidInfo = [self decodeCid:cid];

    if ([cidInfo[@"error"] length] > 0) {
        [response setJsonBody:cidInfo];
        return;
    }

    // Add some additional formatting for display
    NSMutableDictionary *formattedInfo = [cidInfo mutableCopy];
    formattedInfo[@"formatted"] = @{
        @"multibasePrefix": [NSString stringWithFormat:@"%@ (base%d)", cidInfo[@"multibase"],
                           [cidInfo[@"multibase"] isEqualToString:@"b"] ? 32 :
                           [cidInfo[@"multibase"] isEqualToString:@"z"] ? 58 : 0],
        @"codecDescription": [self codecDescriptionForCode:cidInfo[@"codec"] ?: @0],
        @"hashDescription": [self hashDescriptionForCode:cidInfo[@"hashAlgorithm"] ?: @0]
    };

    [response setJsonBody:formattedInfo];
}

- (NSString *)codecDescriptionForCode:(id)code {
    uint64_t codecCode = 0;
    if ([code isKindOfClass:[NSNumber class]]) {
        codecCode = [code unsignedLongLongValue];
    } else if ([code isKindOfClass:[NSString class]]) {
        // Parse hex string like "0x71"
        NSString *hexStr = (NSString *)code;
        if ([hexStr hasPrefix:@"0x"]) {
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&codecCode];
        }
    }
    switch (codecCode) {
        case 0x55: return @"Raw binary data";
        case 0x70: return @"MerkleDAG protobuf";
        case 0x71: return @"MerkleDAG CBOR";
        case 0x72: return @"MerkleDAG JSON";
        case 0x129: return @"DAG-JSON";
        default: return @"Unknown codec";
    }
}

- (NSString *)hashDescriptionForCode:(id)code {
    uint64_t hashCode = 0;
    if ([code isKindOfClass:[NSNumber class]]) {
        hashCode = [code unsignedLongLongValue];
    } else if ([code isKindOfClass:[NSString class]]) {
        // Parse hex string like "0x12"
        NSString *hexStr = (NSString *)code;
        if ([hexStr hasPrefix:@"0x"]) {
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&hashCode];
        }
    }
    switch (hashCode) {
        case 0x11: return @"SHA-1";
        case 0x12: return @"SHA-256 (recommended)";
        case 0x13: return @"SHA-512";
        case 0xb220: return @"Blake2b-256";
        case 0xb240: return @"Blake2b-512";
        default: return @"Unknown hash algorithm";
    }
}

- (NSDictionary *)parseQueryString:(NSString *)query {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            NSString *key = [kv[0] stringByRemovingPercentEncoding];
            NSString *value = [kv[1] stringByRemovingPercentEncoding];
            params[key] = value;
        }
    }
    return [params copy];
}

#pragma mark - API Handlers

- (void)handleApiLookup:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *handle = params[@"handle"];
    
    if (did) {
        NSString *resolvedDid = [self resolveHandleFromDid:did];
        if (resolvedDid) {
            [response setJsonBody:@{@"did": resolvedDid, @"handle": handle ?: resolvedDid}];
        } else {
            [response setJsonBody:@{@"error": @"DID not found"}];
        }
    }
    else if (handle) {
        NSString *resolvedDid = [self resolveHandleToDid:handle];
        if (resolvedDid) {
            [response setJsonBody:@{@"did": resolvedDid, @"handle": handle}];
        } else {
            [response setJsonBody:@{@"error": @"Handle not found"}];
        }
    }
    else {
        [response setJsonBody:@{@"error": @"Missing did or handle parameter"}];
    }
}

- (void)handleApiDid:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSString *cached = [self.cache getDidDocument:did];
    if (cached) {
        NSData *data = [cached dataUsingEncoding:NSUTF8StringEncoding];
        [response setBody:data];
        return;
    }
    
    NSString *doc = [self fetchDidDocument:did];
    if (doc) {
        [self.cache setDidDocument:did value:doc];
        [response setBody:[doc dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to fetch DID document"}];
    }
}

- (void)handleApiPlcLog:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSString *cached = [self.cache getPlcLog:did];
    if (cached) {
        NSData *data = [cached dataUsingEncoding:NSUTF8StringEncoding];
        [response setBody:data];
        return;
    }
    
    NSString *log = [self fetchPlcLog:did];
    if (log) {
        [self.cache setPlcLog:did value:log];
        [response setBody:[log dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to fetch PLC log"}];
    }
}

- (void)handleApiAccounts:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cached = [self.cache getAccountList];
    if (cached) {
        [response setBody:[cached dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    
    NSString *accounts = [self fetchAccountList];
    if (accounts) {
        [self.cache setAccountList:accounts];
        [response setBody:[accounts dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"accounts": @[]}];
    }
}

- (void)handleApiRecords:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *collection = params[@"collection"];
    NSString *did = params[@"did"];
    NSString *limit = params[@"limit"] ?: @"20";
    NSString *cursor = params[@"cursor"];
    
    if (!collection) {
        [response setJsonBody:@{@"error": @"Missing collection parameter"}];
        return;
    }
    
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSString *recordsJson = [self fetchRecordsForCollection:collection did:did limit:limit cursor:cursor];
    if (recordsJson) {
        [response setBody:[recordsJson dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to fetch records"}];
    }
}

- (void)handleApiRecord:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *uri = params[@"uri"];
    if (!uri) {
        [response setJsonBody:@{@"error": @"Missing uri parameter"}];
        return;
    }

    // Extract DID from URI
    NSArray *uriParts = [uri componentsSeparatedByString:@"/"];
    NSString *did = uriParts.count >= 3 ? uriParts[2] : nil;

    if (!did) {
        [response setJsonBody:@{@"error": @"Invalid URI format"}];
        return;
    }

    NSString *errorMessage = nil;
    sqlite3 *db = [self openDatabaseWithError:&errorMessage];

    if (!db) {
        [response setJsonBody:@{@"error": errorMessage ?: @"Failed to open database"}];
        return;
    }

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, "SELECT uri, did, collection, rkey, cid, created_at, value FROM records WHERE uri = ?", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        [response setJsonBody:@{
            @"error": @"Failed to prepare statement",
            @"sqlite_error": @(sqlite3_errmsg(db))
        }];
        sqlite3_close(db);
        return;
    }

    sqlite3_bind_text(stmt, 1, uri.UTF8String, -1, SQLITE_TRANSIENT);

    NSDictionary *recordValue = @{};
    NSString *recordCid = @"";
    NSString *recordCollection = @"";
    NSString *recordRkey = @"";

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *cid = (const char *)sqlite3_column_text(stmt, 4);
        const char *col = (const char *)sqlite3_column_text(stmt, 2);
        const char *rkey = (const char *)sqlite3_column_text(stmt, 3);
        const char *valueStr = (const char *)sqlite3_column_text(stmt, 6);

        recordCid = cid ? @(cid) : @"";
        recordCollection = col ? @(col) : @"";
        recordRkey = rkey ? @(rkey) : @"";

        if (valueStr) {
            NSData *jsonData = [NSData dataWithBytes:valueStr length:strlen(valueStr)];
            NSError *parseError = nil;
            recordValue = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
            if (!recordValue) {
                recordValue = @{@"raw": @(valueStr)};
            }
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (recordCid.length == 0) {
        [response setJsonBody:@{@"error": @"Record not found", @"uri": uri}];
        return;
    }

    [response setJsonBody:@{
        @"uri": uri,
        @"did": did,
        @"cid": recordCid,
        @"collection": recordCollection,
        @"rkey": recordRkey,
        @"value": recordValue
    }];
}

- (void)handleApiBlob:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }
    
    NSData *blobData = [self fetchBlob:cid mimeType:nil];
    if (blobData) {
        response.statusCode = 200;
        [response setHeader:@"application/octet-stream" forKey:@"Content-Type"];
        [response setHeader:[NSString stringWithFormat:@"attachment; filename=\"%@\"", cid] forKey:@"Content-Disposition"];
        [response setBody:blobData];
    } else {
        [response setJsonBody:@{@"error": @"Blob not found"}];
    }
}

- (void)handleApiCidDecode:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }
    
    NSDictionary *decoded = [self decodeCid:cid];
    [response setJsonBody:decoded];
}

#pragma mark - Data Fetching

- (NSString *)fetchDidDocument:(NSString *)did {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", self.plcServerURL, did]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] 
        dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (data) {
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result) {
                    [self.cache setDidDocument:did value:result];
                }
            });
        }
    }];
    [task resume];
    
    NSString *cached = [self.cache getDidDocument:did];
    return cached;
}

- (NSString *)fetchPlcLog:(NSString *)did {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/log/%@", self.plcServerURL, did]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *result = nil;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] 
        dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (data) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    
    return result;
}

- (NSString *)fetchAccountList {
    if (!self.controller) {
        return @"{\"accounts\":[],\"error\":\"PDS controller not configured\"}";
    }

    // Use direct database access like CLI commands do
    // This ensures compatibility with the account creation commands
    NSString *dbPath = [self.controller.dataDirectory stringByAppendingPathComponent:@"pds.db"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        return @"{\"accounts\":[],\"error\":\"Database not found\"}";
    }

    NSError *error = nil;
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return [NSString stringWithFormat:@"{\"accounts\":[],\"error\":\"Failed to open database: %@\"}", error.localizedDescription];
    }

    NSArray<PDSDatabaseAccount *> *accounts = [db getAllAccountsWithError:&error];
    if (error) {
        return [NSString stringWithFormat:@"{\"accounts\":[],\"error\":\"%@\"}", error.localizedDescription];
    }

    // Debug: log the number of accounts found
    NSLog(@"fetchAccountList: Found %lu accounts", (unsigned long)accounts.count);
    
    NSMutableArray *accountArray = [NSMutableArray array];
    for (PDSDatabaseAccount *account in accounts) {
        [accountArray addObject:@{
            @"did": account.did ?: @"",
            @"handle": account.handle ?: @"",
            @"email": account.email ?: [NSNull null],
            @"createdAt": @(account.createdAt),
            @"updatedAt": @(account.updatedAt)
        }];
    }
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"accounts": accountArray}
                                                       options:0
                                                         error:&jsonError];
    if (jsonError) {
        return @"{\"accounts\":[],\"error\":\"Failed to serialize accounts\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)fetchCollectionsForDid:(NSString *)did {
    if (!self.controller || !did) {
        return @"{\"collections\":[],\"error\":\"Controller not configured or DID missing\"}";
    }
    
    NSError *error = nil;
    NSDictionary *repoDesc = [self.controller describeRepo:did error:&error];
    
    if (error || !repoDesc) {
        return [NSString stringWithFormat:@"{\"collections\":[],\"error\":\"%@\"}", 
                error.localizedDescription ?: @"Failed to fetch repo description"];
    }
    
    NSMutableArray *collections = [NSMutableArray array];
    NSArray *knownCollections = @[
        @"app.bsky.actor.profile",
        @"app.bsky.feed.post",
        @"app.bsky.feed.like",
        @"app.bsky.feed.repost",
        @"app.bsky.graph.follow",
        @"app.bsky.graph.block",
        @"app.bsky.graph.list",
        @"app.bsky.graph.listitem",
        @"app.bsky.notification.update",
        @"app.bsky.feed.threadgate",
        @"app.bsky.feed.postgate",
        @"app.bsky.labeler.service",
        @"app.bsky.labeler.subscribed"
    ];
    
    NSString *rootCid = repoDesc[@"root"];
    NSString *repoDid = repoDesc[@"did"];
    
    for (NSString *collection in knownCollections) {
        [collections addObject:collection];
    }
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{
        @"collections": collections,
        @"root": rootCid ?: @"",
        @"did": repoDid ?: did
    } options:0 error:&jsonError];
    
    if (jsonError) {
        return @"{\"collections\":[],\"error\":\"JSON serialization failed\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)fetchRecordsForCollection:(NSString *)collection did:(NSString *)did limit:(NSString *)limitStr cursor:(NSString *)cursor {
    if (!self.controller || !did || !collection) {
        return @"{\"records\":[],\"error\":\"Controller not configured or parameters missing\"}";
    }
    
    NSUInteger limit = limitStr ? [limitStr integerValue] : 20;
    if (limit > 100) limit = 100;
    
    NSError *error = nil;
    NSArray *records = [self.controller listRecords:collection 
                                            forDid:did 
                                              limit:limit 
                                             cursor:cursor 
                                              error:&error];
    
    if (error) {
        return [NSString stringWithFormat:@"{\"records\":[],\"error\":\"%@\"}", error.localizedDescription];
    }
    
    NSMutableArray *recordArray = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSString *uri = record[@"uri"];
        NSString *cid = record[@"cid"];
        NSDictionary *value = record[@"value"];
        
        [recordArray addObject:@{
            @"uri": uri ?: @"",
            @"cid": cid ?: @"",
            @"value": value ?: @{}
        }];
    }
    
    NSError *jsonError = nil;
    NSDictionary *result = @{
        @"records": recordArray,
        @"cursor": cursor ?: [NSNull null]
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:&jsonError];
    
    if (jsonError) {
        return @"{\"records\":[],\"error\":\"JSON serialization failed\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)fetchRecord:(NSString *)uri {
    if (!self.controller || !uri) {
        return nil;
    }
    
    NSError *error = nil;
    // Extract DID from URI
    NSArray *uriParts = [uri componentsSeparatedByString:@"/"];
    NSString *did = uriParts.count >= 2 ? uriParts[2] : nil;
    NSDictionary *record = [self.controller getRecord:uri forDid:did error:&error];
    
    if (error || !record) {
        return nil;
    }
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:&jsonError];
    
    if (jsonError) {
        return nil;
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSData *)fetchBlob:(NSString *)cid mimeType:(NSString **)outMimeType {
    return nil;
}

- (NSDictionary *)decodeCid:(NSString *)cid {
    if (!cid || cid.length < 2) {
        return @{@"error": @"Invalid CID"};
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"input"] = cid;
    result[@"length"] = @(cid.length);

    unichar firstChar = [cid characterAtIndex:0];
    result[@"multibase"] = [NSString stringWithFormat:@"%C", firstChar];
    result[@"multibaseDescription"] = [self multibaseDescriptionForChar:firstChar];

    // Handle CIDv0 (starts with 'Q')
    if (firstChar == 'Q') {
        result[@"version"] = @(0);
        result[@"codec"] = @"0x70"; // dag-pb is implicit for v0
        result[@"codecName"] = @"dag-pb (implicit)";
        result[@"hashAlgorithm"] = @"0x12"; // sha2-256 is implicit for v0
        result[@"hashAlgorithmName"] = @"SHA-256 (implicit)";
        result[@"cidType"] = @"CIDv0";
        result[@"description"] = @"CIDv0 uses base58btc encoding with implicit dag-pb codec and sha2-256 hash";
        return result;
    }

    // For CIDv1, decode the actual binary structure
    NSString *encoded = [cid substringFromIndex:1];
    result[@"encodedPayload"] = encoded;
    result[@"payloadLength"] = @(encoded.length);

    // Decode based on multibase encoding
    NSData *decodedData = nil;
    if (firstChar == 'b') {
        // Use built-in base32 decoding if available, otherwise fall back to custom
        decodedData = [self base32Decode:encoded];
        if (!decodedData) {
            result[@"error"] = @"Failed to decode base32 payload";
            return result;
        }
    } else if (firstChar == 'z') {
        // base58btc decoding would go here - for now return basic info
        result[@"version"] = @(1);
        result[@"cidType"] = @"CIDv1";
        result[@"description"] = @"CIDv1 with base58btc encoding - full decoding requires base58 library";
        result[@"structure"] = @"<multibase-prefix><cid-version><multicodec><multihash>";
        result[@"decodingStatus"] = @"partial - base58 decoding not implemented";
        return result;
    } else {
        result[@"error"] = [NSString stringWithFormat:@"Unsupported multibase encoding: %C", firstChar];
        return result;
    }

    if (!decodedData || decodedData.length == 0) {
        result[@"error"] = @"Failed to decode multibase payload";
        return result;
    }

    // Parse CIDv1 binary structure
    const uint8_t *bytes = [decodedData bytes];
    NSUInteger length = decodedData.length;
    NSUInteger offset = 0;



    // Version (should be 1 for CIDv1)
    if (offset >= length) {
        result[@"error"] = @"CID too short for version";
        return result;
    }

    uint8_t version = bytes[offset++];
    result[@"version"] = @(version);

    if (version != 1) {
        result[@"error"] = [NSString stringWithFormat:@"Unsupported CID version: %d", version];
        return result;
    }

    // Decode multicodec (varint)
    uint64_t codec = [self decodeVarint:bytes length:length offset:&offset];
    result[@"codec"] = [NSString stringWithFormat:@"0x%llx", codec];
    result[@"codecName"] = [self codecNameForCode:codec];

    // Decode multihash
    if (offset >= length) {
        result[@"error"] = @"Incomplete multihash";
        return result;
    }

    uint64_t hashAlg = [self decodeVarint:bytes length:length offset:&offset];
    result[@"hashAlgorithm"] = [NSString stringWithFormat:@"0x%llx", hashAlg];
    result[@"hashAlgorithmName"] = [self hashNameForCode:hashAlg];

    if (offset >= length) {
        result[@"error"] = @"Incomplete hash size";
        return result;
    }

    uint8_t hashSize = bytes[offset++];
    result[@"hashSize"] = @(hashSize);

    if (offset + hashSize > length) {
        result[@"error"] = @"Incomplete hash digest";
        return result;
    }

    NSMutableString *digest = [NSMutableString string];
    for (NSUInteger i = 0; i < hashSize; i++) {
        [digest appendFormat:@"%02x", bytes[offset + i]];
    }
    result[@"digest"] = digest;
    result[@"cidType"] = @"CIDv1";

    return result;
}

- (uint64_t)decodeVarint:(const uint8_t *)bytes length:(NSUInteger)length offset:(NSUInteger *)offset {
    uint64_t value = 0;
    int shift = 0;
    NSUInteger startOffset = *offset;

    while (*offset < length && shift < 64) {
        uint8_t byte = bytes[*offset];
        (*offset)++;

        // Add the 7 low bits to the value
        value |= ((uint64_t)(byte & 0x7f)) << shift;
        shift += 7;

        // If high bit is not set, this is the last byte
        if (!(byte & 0x80)) {
            break;
        }

        // Prevent infinite loop on malformed data (varints should be at most 9 bytes for uint64)
        if (*offset - startOffset > 9) {
            break;
        }
    }

    return value;
}

- (NSData *)base32Decode:(NSString *)input {
    // Base32 alphabet (RFC 4648 lowercase)
    NSDictionary *alphabetMap = @{
        @"a": @0, @"b": @1, @"c": @2, @"d": @3, @"e": @4, @"f": @5,
        @"g": @6, @"h": @7, @"i": @8, @"j": @9, @"k": @10, @"l": @11,
        @"m": @12, @"n": @13, @"o": @14, @"p": @15, @"q": @16, @"r": @17,
        @"s": @18, @"t": @19, @"u": @20, @"v": @21, @"w": @22, @"x": @23,
        @"y": @24, @"z": @25, @"2": @26, @"3": @27, @"4": @28, @"5": @29,
        @"6": @30, @"7": @31
    };

    NSMutableData *output = [NSMutableData data];
    uint32_t buffer = 0;
    NSUInteger bitsLeft = 0;

    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        NSString *charStr = [NSString stringWithCharacters:&c length:1];
        NSNumber *val = alphabetMap[charStr];

        if (!val) continue; // Skip invalid characters

        buffer = (buffer << 5) | [val intValue];
        bitsLeft += 5;

        while (bitsLeft >= 8) {
            bitsLeft -= 8;
            uint8_t byte = (buffer >> bitsLeft) & 0xFF;
            [output appendBytes:&byte length:1];
        }
    }

    return output;
}

- (NSString *)multibaseDescriptionForChar:(unichar)c {
    switch (c) {
        case 'b': return @"base32 (RFC4648 lowercase)";
        case 'B': return @"base32 (RFC4648 uppercase)";
        case 'c': return @"base32hex (RFC4648 lowercase)";
        case 'C': return @"base32hex (RFC4648 uppercase)";
        case 'f': return @"base16 (hex lowercase)";
        case 'F': return @"base16 (hex uppercase)";
        case 'k': return @"base36 (lowercase)";
        case 'K': return @"base36 (uppercase)";
        case 'm': return @"base64 (RFC4648 no padding)";
        case 'M': return @"base64 (RFC4648 with padding)";
        case 'p': return @"base64url (RFC4648 no padding)";
        case 'P': return @"base64url (RFC4648 with padding)";
        case 't': return @"base64url (no padding)";
        case 'T': return @"base64url (with padding)";
        case 'v': return @"base32hex (no padding)";
        case 'V': return @"base32hex (with padding)";
        case 'w': return @"base32hex (no padding)";
        case 'W': return @"base32hex (with padding)";
        case 'x': return @"base16 (no padding)";
        case 'X': return @"base16 (with padding)";
        case 'y': return @"base64 (no padding)";
        case 'Y': return @"base64 (with padding)";
        case 'z': return @"base58btc";
        case 'Z': return @"base58flickr";
        case '0': return @"base2";
        case '1': return @"base8";
        case '2': return @"base10";
        case '9': return @"base36";
        case 'a': return @"base36";
        default: return @"unknown multibase encoding";
    }
}

- (NSString *)codecNameForCode:(uint64_t)code {
    switch (code) {
        case 0x00: return @"identity";
        case 0x01: return @"cidv1";
        case 0x02: return @"cidv2";
        case 0x03: return @"cidv3";
        case 0x04: return @"ip4";
        case 0x06: return @"ip6";
        case 0x0a: return @"ipcidr";
        case 0x21: return @"port";
        case 0x2f: return @"dccp";
        case 0x33: return @"sctp";
        case 0x35: return @"tcp";
        case 0x36: return @"udp";
        case 0x55: return @"raw";
        case 0x56: return @"cbor";
        case 0x70: return @"dag-pb";
        case 0x71: return @"dag-cbor";
        case 0x72: return @"dag-json";
        case 0x78: return @"git-raw";
        case 0x7b: return @"eth-block";
        case 0x7c: return @"eth-block-list";
        case 0x81: return @"eth-tx-trie";
        case 0x82: return @"eth-tx";
        case 0x83: return @"eth-tx-receipt-trie";
        case 0x84: return @"eth-tx-receipt";
        case 0x85: return @"eth-state-trie";
        case 0x86: return @"eth-account-snapshot";
        case 0x87: return @"eth-storage-trie";
        case 0x90: return @"bitcoin-block";
        case 0x91: return @"bitcoin-tx";
        case 0x92: return @"bitcoin-witness-commitment";
        case 0xb0: return @"zcash-block";
        case 0xb1: return @"zcash-tx";
        case 0xc0: return @"decred-block";
        case 0xc1: return @"decred-tx";
        case 0xce: return @"ipld-ns";
        case 0xd0: return @"fil-commitment-unsealed";
        case 0xd1: return @"fil-commitment-sealed";
        case 0xe0: return @"holochain-adr-v0";
        case 0xe1: return @"holochain-adr-v1";
        case 0xe2: return @"holochain-key-v0";
        case 0xe3: return @"holochain-key-v1";
        case 0xe4: return @"holochain-sig-v0";
        case 0xe5: return @"holochain-sig-v1";
        case 0x0129: return @"dag-json";
        case 0x85e: return @"dash-block";
        case 0x85f: return @"dash-tx";
        case 0xb199: return @"swarm-manifest";
        case 0xb19a: return @"swarm-feed";
        case 0xc219: return @"tcp";
        case 0xc21a: return @"udp";
        case 0xc220: return @"ipfs";
        case 0xc221: return @"ipfs-ns";
        case 0xc226: return @"onion";
        case 0xc227: return @"onion3";
        case 0xc228: return @"garlic64";
        case 0xc229: return @"garlic32";
        case 0xc230: return @"p2p-circuit";
        case 0xc400: return @"ipfs";
        case 0xc401: return @"ipfs-ns";
        case 0xc402: return @"swarm";
        case 0xc403: return @"ipfs-ns";
        case 0xc404: return @"zeronet";
        case 0xc405: return @"ipfs-ns";
        case 0xc406: return @"cbor";
        case 0xc500: return @"ipns-ns";
        case 0xc501: return @"swarm-ns";
        case 0xc502: return @"ipns-ns";
        case 0xc503: return @"zeronet-ns";
        case 0xc504: return @"ipns-ns";
        case 0xc600: return @"path";
        case 0xc700: return @"multihash";
        case 0xc701: return @"multiaddr";
        case 0xc702: return @"multibase";
        case 0xc800: return @"dns4";
        case 0xc801: return @"dns6";
        case 0xc802: return @"dnsaddr";
        case 0xc803: return @"dnsaddr";
        case 0xc900: return @"dns";
        case 0xca00: return @"dns4";
        case 0xca01: return @"dns6";
        case 0xca02: return @"dnsaddr";
        case 0xd000: return @"protobuf";
        case 0xd100: return @"cbor";
        case 0xd200: return @"raw";
        case 0xd300: return @"dbl-sha2-256";
        case 0xe200: return @"eth-hash";
        case 0xe201: return @"eth-state-trie";
        case 0xe202: return @"eth-block";
        case 0xe203: return @"eth-block-list";
        case 0xe204: return @"eth-tx-trie";
        case 0xe205: return @"eth-tx";
        case 0xe206: return @"eth-tx-receipt-trie";
        case 0xe207: return @"eth-tx-receipt";
        case 0xe208: return @"eth-account-snapshot";
        case 0xe209: return @"eth-storage-trie";
        case 0xe300: return @"eth-tx-receipt-trie";
        case 0xe301: return @"eth-tx-receipt";
        case 0xe302: return @"eth-state-trie";
        case 0xe303: return @"eth-account-snapshot";
        case 0xe304: return @"eth-storage-trie";
        case 0xf000: return @"bitcoin-block";
        case 0xf001: return @"bitcoin-tx";
        case 0xf002: return @"bitcoin-witness-commitment";
        case 0xf100: return @"zcash-block";
        case 0xf101: return @"zcash-tx";
        case 0xf200: return @"decred-block";
        case 0xf201: return @"decred-tx";
        default: return [NSString stringWithFormat:@"unknown (0x%llx)", code];
    }
}

- (NSString *)hashNameForCode:(uint64_t)code {
    switch (code) {
        case 0x00: return @"identity";
        case 0x11: return @"sha1";
        case 0x12: return @"sha2-256";
        case 0x13: return @"sha2-512";
        case 0x14: return @"sha3-512";
        case 0x15: return @"sha3-384";
        case 0x16: return @"sha3-256";
        case 0x17: return @"sha3-224";
        case 0x18: return @"shake-128";
        case 0x19: return @"shake-256";
        case 0x1a: return @"keccak-224";
        case 0x1b: return @"keccak-256";
        case 0x1c: return @"keccak-384";
        case 0x1d: return @"keccak-512";
        case 0x20: return @"blake3";
        case 0x21: return @"sha3-512";
        case 0x22: return @"sha3-384";
        case 0x23: return @"sha3-256";
        case 0x24: return @"sha3-224";
        case 0x25: return @"shake-128";
        case 0x26: return @"shake-256";
        case 0x27: return @"keccak-224";
        case 0x28: return @"keccak-256";
        case 0x29: return @"keccak-384";
        case 0x2a: return @"keccak-512";
        case 0xb201: return @"blake2b-8";
        case 0xb202: return @"blake2b-16";
        case 0xb203: return @"blake2b-24";
        case 0xb204: return @"blake2b-32";
        case 0xb205: return @"blake2b-40";
        case 0xb206: return @"blake2b-48";
        case 0xb207: return @"blake2b-56";
        case 0xb208: return @"blake2b-64";
        case 0xb209: return @"blake2b-72";
        case 0xb20a: return @"blake2b-80";
        case 0xb20b: return @"blake2b-88";
        case 0xb20c: return @"blake2b-96";
        case 0xb20d: return @"blake2b-104";
        case 0xb20e: return @"blake2b-112";
        case 0xb20f: return @"blake2b-120";
        case 0xb210: return @"blake2b-128";
        case 0xb211: return @"blake2b-136";
        case 0xb212: return @"blake2b-144";
        case 0xb213: return @"blake2b-152";
        case 0xb214: return @"blake2b-160";
        case 0xb215: return @"blake2b-168";
        case 0xb216: return @"blake2b-176";
        case 0xb217: return @"blake2b-184";
        case 0xb218: return @"blake2b-192";
        case 0xb219: return @"blake2b-200";
        case 0xb21a: return @"blake2b-208";
        case 0xb21b: return @"blake2b-216";
        case 0xb21c: return @"blake2b-224";
        case 0xb21d: return @"blake2b-232";
        case 0xb21e: return @"blake2b-240";
        case 0xb21f: return @"blake2b-248";
        case 0xb220: return @"blake2b-256";
        case 0xb221: return @"blake2b-264";
        case 0xb222: return @"blake2b-272";
        case 0xb223: return @"blake2b-280";
        case 0xb224: return @"blake2b-288";
        case 0xb225: return @"blake2b-296";
        case 0xb226: return @"blake2b-304";
        case 0xb227: return @"blake2b-312";
        case 0xb228: return @"blake2b-320";
        case 0xb229: return @"blake2b-328";
        case 0xb22a: return @"blake2b-336";
        case 0xb22b: return @"blake2b-344";
        case 0xb22c: return @"blake2b-352";
        case 0xb22d: return @"blake2b-360";
        case 0xb22e: return @"blake2b-368";
        case 0xb22f: return @"blake2b-376";
        case 0xb230: return @"blake2b-384";
        case 0xb231: return @"blake2b-392";
        case 0xb232: return @"blake2b-400";
        case 0xb233: return @"blake2b-408";
        case 0xb234: return @"blake2b-416";
        case 0xb235: return @"blake2b-424";
        case 0xb236: return @"blake2b-432";
        case 0xb237: return @"blake2b-440";
        case 0xb238: return @"blake2b-448";
        case 0xb239: return @"blake2b-456";
        case 0xb23a: return @"blake2b-464";
        case 0xb23b: return @"blake2b-472";
        case 0xb23c: return @"blake2b-480";
        case 0xb23d: return @"blake2b-488";
        case 0xb23e: return @"blake2b-496";
        case 0xb23f: return @"blake2b-504";
        case 0xb240: return @"blake2b-512";
        case 0xb241: return @"blake2s-8";
        case 0xb242: return @"blake2s-16";
        case 0xb243: return @"blake2s-24";
        case 0xb244: return @"blake2s-32";
        case 0xb245: return @"blake2s-40";
        case 0xb246: return @"blake2s-48";
        case 0xb247: return @"blake2s-56";
        case 0xb248: return @"blake2s-64";
        case 0xb249: return @"blake2s-72";
        case 0xb24a: return @"blake2s-80";
        case 0xb24b: return @"blake2s-88";
        case 0xb24c: return @"blake2s-96";
        case 0xb24d: return @"blake2s-104";
        case 0xb24e: return @"blake2s-112";
        case 0xb24f: return @"blake2s-120";
        case 0xb250: return @"blake2s-128";
        case 0xb251: return @"blake2s-136";
        case 0xb252: return @"blake2s-144";
        case 0xb253: return @"blake2s-152";
        case 0xb254: return @"blake2s-160";
        case 0xb255: return @"blake2s-168";
        case 0xb256: return @"blake2s-176";
        case 0xb257: return @"blake2s-184";
        case 0xb258: return @"blake2s-192";
        case 0xb259: return @"blake2s-200";
        case 0xb25a: return @"blake2s-208";
        case 0xb25b: return @"blake2s-216";
        case 0xb25c: return @"blake2s-224";
        case 0xb25d: return @"blake2s-232";
        case 0xb25e: return @"blake2s-240";
        case 0xb25f: return @"blake2s-248";
        case 0xb260: return @"blake2s-256";
        default: return [NSString stringWithFormat:@"unknown (0x%llx)", code];
    }
}

- (NSString *)resolveHandleToDid:(NSString *)handle {
    return nil;
}

- (NSString *)resolveHandleFromDid:(NSString *)did {
    return did;
}

#pragma mark - OpenAPI Spec Generation

- (NSArray<APIEndpointDescriptor *> *)allEndpointDescriptors {
    NSMutableArray *descriptors = [NSMutableArray array];

    APIParameterDescriptor *didParam = [[APIParameterDescriptor alloc] init];
    didParam.name = @"did";
    didParam.in = @"query";
    didParam.type = @"string";
    didParam.paramDescription = @"The DID of the account or repository";
    didParam.required = NO;

    APIParameterDescriptor *collectionParam = [[APIParameterDescriptor alloc] init];
    collectionParam.name = @"collection";
    collectionParam.in = @"query";
    collectionParam.type = @"string";
    collectionParam.paramDescription = @"The collection namespace (e.g., app.bsky.feed.post)";
    collectionParam.required = NO;

    APIParameterDescriptor *uriParam = [[APIParameterDescriptor alloc] init];
    uriParam.name = @"uri";
    uriParam.in = @"query";
    uriParam.type = @"string";
    uriParam.paramDescription = @"The AT Protocol URI (at://did/collection/rkey)";
    uriParam.required = YES;

    APIParameterDescriptor *limitParam = [[APIParameterDescriptor alloc] init];
    limitParam.name = @"limit";
    limitParam.in = @"query";
    limitParam.type = @"integer";
    limitParam.paramDescription = @"Maximum number of records to return (default 50, max 200)";
    limitParam.required = NO;

    APIResponseDescriptor *accountsArrayResponse = [[APIResponseDescriptor alloc] init];
    accountsArrayResponse.statusCode = @"200";
    accountsArrayResponse.responseDescription = @"Array of account objects";
    accountsArrayResponse.arrayItemRef = @"#/components/schemas/Account";

    APIResponseDescriptor *reposArrayResponse = [[APIResponseDescriptor alloc] init];
    reposArrayResponse.statusCode = @"200";
    reposArrayResponse.responseDescription = @"Array of repository objects";
    reposArrayResponse.arrayItemRef = @"#/components/schemas/Repository";

    APIResponseDescriptor *collectionsArrayResponse = [[APIResponseDescriptor alloc] init];
    collectionsArrayResponse.statusCode = @"200";
    collectionsArrayResponse.responseDescription = @"Array of collection objects with record counts";
    collectionsArrayResponse.arrayItemRef = @"#/components/schemas/Collection";

    APIResponseDescriptor *recordsArrayResponse = [[APIResponseDescriptor alloc] init];
    recordsArrayResponse.statusCode = @"200";
    recordsArrayResponse.responseDescription = @"Array of record objects";
    recordsArrayResponse.arrayItemRef = @"#/components/schemas/Record";

    APIResponseDescriptor *recordResponse = [[APIResponseDescriptor alloc] init];
    recordResponse.statusCode = @"200";
    recordResponse.responseDescription = @"Record details with value";
    recordResponse.schemaRef = @"#/components/schemas/Record";

    APIResponseDescriptor *error400 = [[APIResponseDescriptor alloc] init];
    error400.statusCode = @"400";
    error400.responseDescription = @"Bad request - missing required parameters";

    APIResponseDescriptor *error404 = [[APIResponseDescriptor alloc] init];
    error404.statusCode = @"404";
    error404.responseDescription = @"Resource not found";

    APIResponseDescriptor *errorResponse = [[APIResponseDescriptor alloc] init];
    errorResponse.statusCode = @"500";
    errorResponse.responseDescription = @"Internal server error";
    errorResponse.schemaRef = @"#/components/schemas/Error";

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/accounts"
                                                              method:@"get"
                                                             summary:@"List all accounts"
                                                        endpointName:@"accounts"
                                                        operationId:@"listAccounts"
                                                               tags:@[@"Accounts"]
                                                          parameters:@[]
                                                          responses:@[accountsArrayResponse, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/repositories"
                                                              method:@"get"
                                                             summary:@"List all repositories (PDS instances)"
                                                        endpointName:@"repositories"
                                                        operationId:@"listRepositories"
                                                               tags:@[@"Repositories"]
                                                          parameters:@[]
                                                          responses:@[reposArrayResponse, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/collections"
                                                              method:@"get"
                                                             summary:@"List collections for a repository"
                                                        endpointName:@"collections"
                                                        operationId:@"listCollections"
                                                               tags:@[@"Collections"]
                                                          parameters:@[didParam]
                                                          responses:@[collectionsArrayResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/describe"
                                                              method:@"get"
                                                             summary:@"Describe a repository"
                                                        endpointName:@"describe"
                                                        operationId:@"describeRepository"
                                                               tags:@[@"Repositories"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              [self responseWithStatusCode:@"200" description:@"Repository description with collections and record count"],
                                                              error400, error404, errorResponse
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/account-records"
                                                              method:@"get"
                                                             summary:@"List records for an account"
                                                        endpointName:@"account-records"
                                                        operationId:@"listAccountRecords"
                                                               tags:@[@"Records"]
                                                          parameters:@[didParam, collectionParam, limitParam]
                                                          responses:@[recordsArrayResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/record"
                                                              method:@"get"
                                                             summary:@"Get a single record by URI"
                                                        endpointName:@"record"
                                                        operationId:@"getRecord"
                                                               tags:@[@"Records"]
                                                          parameters:@[uriParam]
                                                          responses:@[recordResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/record-details"
                                                              method:@"get"
                                                             summary:@"Get detailed record information"
                                                        endpointName:@"record-details"
                                                        operationId:@"getRecordDetails"
                                                               tags:@[@"Records"]
                                                          parameters:@[uriParam]
                                                          responses:@[recordResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/account-details"
                                                              method:@"get"
                                                             summary:@"Get account details"
                                                        endpointName:@"account-details"
                                                        operationId:@"getAccountDetails"
                                                               tags:@[@"Accounts"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              [self responseWithStatusCode:@"200" description:@"Account details"],
                                                              error400, error404, errorResponse
                                                          ]]];

    APIParameterDescriptor *valueParam = [[APIParameterDescriptor alloc] init];
    valueParam.name = @"value";
    valueParam.in = @"query";
    valueParam.type = @"string";
    valueParam.paramDescription = @"JSON object as string containing the record value";
    valueParam.required = YES;

    APIParameterDescriptor *createDidParam = [[APIParameterDescriptor alloc] init];
    createDidParam.name = @"did";
    createDidParam.in = @"query";
    createDidParam.type = @"string";
    createDidParam.paramDescription = @"The DID of the repository";
    createDidParam.required = YES;

    APIParameterDescriptor *createCollectionParam = [[APIParameterDescriptor alloc] init];
    createCollectionParam.name = @"collection";
    createCollectionParam.in = @"query";
    createCollectionParam.type = @"string";
    createCollectionParam.paramDescription = @"The collection namespace (e.g., app.bsky.feed.post)";
    createCollectionParam.required = YES;

    APIParameterDescriptor *createRkeyParam = [[APIParameterDescriptor alloc] init];
    createRkeyParam.name = @"rkey";
    createRkeyParam.in = @"query";
    createRkeyParam.type = @"string";
    createRkeyParam.paramDescription = @"The record key (unique within collection)";
    createRkeyParam.required = YES;

    APIResponseDescriptor *createResponse = [[APIResponseDescriptor alloc] init];
    createResponse.statusCode = @"200";
    createResponse.responseDescription = @"Created record with URI, CID, and value";
    createResponse.schemaRef = @"#/components/schemas/CreatedRecord";

    APIResponseDescriptor *resolvedIdentityResponse = [self responseWithStatusCode:@"200" description:@"Resolved identity"];
    APIResponseDescriptor *didDocResponse = [self responseWithStatusCode:@"200" description:@"DID document (JSON)"];
    APIResponseDescriptor *plcLogResponse = [self responseWithStatusCode:@"200" description:@"PLC operation log"];
    APIResponseDescriptor *cidInfoResponse = [self responseWithStatusCode:@"200" description:@"CID information"];
    APIResponseDescriptor *blobResponse = [self responseWithStatusCode:@"200" description:@"Blob data"];

    APIParameterDescriptor *cidParamDecode = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"CID to decode" required:YES];
    APIParameterDescriptor *cidParamInfo = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"CID to look up" required:YES];
    APIParameterDescriptor *blobDidParam = [self paramWithName:@"did" in:@"query" type:@"string" description:@"Repository DID" required:YES];
    APIParameterDescriptor *blobCidParam = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"Blob CID" required:YES];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/create-record"
                                                              method:@"post"
                                                             summary:@"Create a new record"
                                                        endpointName:@"create-record"
                                                        operationId:@"createRecord"
                                                               tags:@[@"Records"]
                                                          parameters:@[createDidParam, createCollectionParam, createRkeyParam, valueParam]
                                                          responses:@[createResponse, error400, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/lookup"
                                                              method:@"get"
                                                             summary:@"Resolve handle to DID or DID to handle"
                                                        endpointName:@"lookup"
                                                        operationId:@"resolveIdentity"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              resolvedIdentityResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/did"
                                                              method:@"get"
                                                             summary:@"Fetch DID document"
                                                        endpointName:@"did"
                                                        operationId:@"getDidDocument"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              didDocResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/plc-log"
                                                              method:@"get"
                                                             summary:@"Get PLC operation log"
                                                        endpointName:@"plc-log"
                                                        operationId:@"getPlcLog"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              plcLogResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/cid-decode"
                                                              method:@"get"
                                                             summary:@"Decode and describe a CID"
                                                        endpointName:@"cid-decode"
                                                        operationId:@"decodeCid"
                                                               tags:@[@"Content"]
                                                          parameters:@[cidParamDecode]
                                                          responses:@[
                                                              cidInfoResponse,
                                                              error400
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/cid-info"
                                                              method:@"get"
                                                             summary:@"Get information about a CID"
                                                        endpointName:@"cid-info"
                                                        operationId:@"getCidInfo"
                                                               tags:@[@"Content"]
                                                          parameters:@[cidParamInfo]
                                                          responses:@[
                                                              cidInfoResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/explore/api/blob"
                                                              method:@"get"
                                                             summary:@"Get blob data"
                                                        endpointName:@"blob"
                                                        operationId:@"getBlob"
                                                               tags:@[@"Content"]
                                                          parameters:@[blobDidParam, blobCidParam]
                                                          responses:@[
                                                              blobResponse,
                                                              error400, error404
                                                          ]]];

    return [descriptors copy];
}

- (APIResponseDescriptor *)responseWithStatusCode:(NSString *)statusCode description:(NSString *)description {
    APIResponseDescriptor *resp = [[APIResponseDescriptor alloc] init];
    resp.statusCode = statusCode;
    resp.responseDescription = description;
    return resp;
}

- (APIParameterDescriptor *)paramWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required {
    APIParameterDescriptor *param = [[APIParameterDescriptor alloc] init];
    param.name = name;
    param.in = inLocation;
    param.type = type;
    param.paramDescription = description;
    param.required = required;
    return param;
}

- (NSDictionary *)generateOpenAPISpec {
    NSMutableDictionary *spec = [NSMutableDictionary dictionary];
    spec[@"openapi"] = @"3.0.0";

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"title"] = @"ATProto PDS Explore API";
    info[@"description"] = @"REST API for exploring AT Protocol PDS data including accounts, repositories, records, and collections. This API provides read-only access to PDS data for development and debugging purposes.";
    info[@"version"] = @"1.0.0";

    NSMutableDictionary *contact = [NSMutableDictionary dictionary];
    contact[@"name"] = @"ATProto PDS Developer Support";
    contact[@"url"] = @"https://github.com/bluesky-social/atproto/blob/main/packages/pds/README.md";
    info[@"contact"] = contact;

    NSMutableDictionary *license = [NSMutableDictionary dictionary];
    license[@"name"] = @"MIT License";
    license[@"url"] = @"https://opensource.org/licenses/MIT";
    info[@"license"] = license;

    spec[@"info"] = info;

    NSMutableDictionary *externalDocs = [NSMutableDictionary dictionary];
    externalDocs[@"description"] = @"ATProto PDS Documentation";
    externalDocs[@"url"] = @"https://atproto.com/docs";
    spec[@"externalDocs"] = externalDocs;

    NSMutableArray *servers = [NSMutableArray array];
    [servers addObject:@{@"url": @"/explore/api", @"description": @"Local development server"}];
    spec[@"servers"] = servers;

    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    NSArray<APIEndpointDescriptor *> *endpoints = [self allEndpointDescriptors];

    for (APIEndpointDescriptor *endpoint in endpoints) {
        NSString *pathKey = endpoint.path;
        NSString *methodKey = [endpoint.method lowercaseString];

        NSMutableDictionary *operation = [[endpoint openAPIDict] mutableCopy];

        NSMutableDictionary *pathItem = paths[pathKey];
        if (!pathItem) {
            pathItem = [NSMutableDictionary dictionary];
            paths[pathKey] = pathItem;
        }
        pathItem[methodKey] = operation;
    }

    spec[@"paths"] = paths;

    NSMutableDictionary *components = [NSMutableDictionary dictionary];
    NSMutableDictionary *schemas = [NSMutableDictionary dictionary];

    schemas[@"Account"] = @{
        @"type": @"object",
        @"description": @"Represents a PDS account with identity information",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Account DID (Decentralized Identifier)", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"handle": @{@"type": @"string", @"description": @"Account handle (e.g., alice.example.com)", @"example": @"alice.example.com"},
            @"email": @{@"type": @"string", @"description": @"Account email address", @"nullable": @YES, @"example": @"alice@example.com"},
            @"createdAt": @{@"type": @"integer", @"description": @"Unix timestamp of account creation", @"example": @(1704752400)},
            @"updatedAt": @{@"type": @"integer", @"description": @"Unix timestamp of last update", @"example": @(1704752400)}
        }
    };

    schemas[@"Repository"] = @{
        @"type": @"object",
        @"description": @"Represents a PDS repository instance",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"handle": @{@"type": @"string", @"description": @"Repository handle", @"example": @"alice.example.com"},
            @"email": @{@"type": @"string", @"description": @"Contact email", @"nullable": @YES, @"example": @"alice@example.com"},
            @"createdAt": @{@"type": @"integer", @"description": @"Creation timestamp", @"example": @(1704752400)},
            @"updatedAt": @{@"type": @"integer", @"description": @"Last update timestamp", @"example": @(1704752400)}
        }
    };

    schemas[@"Collection"] = @{
        @"type": @"object",
        @"description": @"Represents a collection namespace within a repository with record count",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace (e.g., app.bsky.feed.post)", @"example": @"app.bsky.feed.post"},
            @"count": @{@"type": @"integer", @"description": @"Number of records in collection", @"example": @(15)}
        }
    };

    schemas[@"Record"] = @{
        @"type": @"object",
        @"description": @"Represents an AT Protocol record with content and metadata",
        @"properties": @{
            @"uri": @{@"type": @"string", @"description": @"Record URI (at://did/collection/rkey)", @"example": @"at://did:plc:g3x5vnga7kiu3oaookgeozpb/app.bsky.feed.post/3k5d3f4g5h6j7"},
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace", @"example": @"app.bsky.feed.post"},
            @"rkey": @{@"type": @"string", @"description": @"Record key (unique within collection)", @"example": @"3k5d3f4g5h6j7"},
            @"cid": @{@"type": @"string", @"description": @"Content ID of the record value", @"example": @"bafyreifac123"},
            @"value": @{@"type": @"object", @"description": @"Record content as JSON object"},
            @"createdAt": @{@"type": @"string", @"description": @"ISO 8601 timestamp of record creation", @"example": @"2024-01-08T20:30:00Z"}
        }
    };

    schemas[@"CreatedRecord"] = @{
        @"type": @"object",
        @"description": @"Response from creating a new record",
        @"properties": @{
            @"uri": @{@"type": @"string", @"description": @"Created record URI", @"example": @"at://did:plc:g3x5vnga7kiu3oaookgeozpb/app.bsky.feed.post/newkey"},
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace", @"example": @"app.bsky.feed.post"},
            @"rkey": @{@"type": @"string", @"description": @"Record key", @"example": @"newkey"},
            @"cid": @{@"type": @"string", @"description": @"Generated CID", @"example": @"bafyreinewcid"},
            @"value": @{@"type": @"object", @"description": @"Record value that was stored"},
            @"createdAt": @{@"type": @"string", @"description": @"ISO 8601 timestamp", @"example": @"2024-01-08T20:30:00Z"}
        }
    };

    schemas[@"Error"] = @{
        @"type": @"object",
        @"description": @"Standard error response (RFC 7807 Problem Details format)",
        @"properties": @{
            @"type": @{@"type": @"string", @"description": @"Error type identifier", @"example": @"https://atproto.com/errors/bad-request"},
            @"title": @{@"type": @"string", @"description": @"Short human-readable error title", @"example": @"Bad Request"},
            @"status": @{@"type": @"integer", @"description": @"HTTP status code", @"example": @(400)},
            @"detail": @{@"type": @"string", @"description": @"Detailed error description", @"example": @"Missing required parameter: did"},
            @"instance": @{@"type": @"string", @"description": @"URI reference that identifies the specific occurrence"}
        }
    };

    components[@"schemas"] = schemas;
    spec[@"components"] = components;

    return [spec copy];
}

- (NSString *)jsonToYAML:(NSDictionary *)json indent:(NSUInteger)indent {
    NSMutableString *yaml = [NSMutableString string];
    NSString *spaces = [@"" stringByPaddingToLength:indent withString:@" " startingAtIndex:0];

    NSArray *sortedKeys = [[json allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in sortedKeys) {
        id value = json[key];

        [yaml appendFormat:@"%@", spaces];

        if ([value isKindOfClass:[NSDictionary class]]) {
            [yaml appendFormat:@"%@:\n", key];
            [yaml appendString:[self jsonToYAML:value indent:indent + 2]];
        } else if ([value isKindOfClass:[NSArray class]]) {
            [yaml appendFormat:@"%@:\n", key];
            for (id item in value) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [yaml appendString:[self jsonToYAML:item indent:indent + 2]];
                } else {
                    [yaml appendFormat:@"%@  - %@\n", spaces, item];
                }
            }
        } else if ([value isKindOfClass:[NSString class]]) {
            NSString *strValue = (NSString *)value;
            if ([strValue containsString:@":"] || [strValue containsString:@"{"] || [strValue containsString:@"}"] || [strValue containsString:@"["] || [strValue containsString:@"]"] || [strValue hasPrefix:@"/"] || [strValue hasPrefix:@"#"] || [strValue isEqualToString:@"~"] || [strValue isEqualToString:@"null"] || [strValue isEqualToString:@"true"] || [strValue isEqualToString:@"false"] || strValue.length == 0) {
                [yaml appendFormat:@"%@: \"%@\"\n", key, [strValue stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
            } else {
                [yaml appendFormat:@"%@: %@\n", key, strValue];
            }
        } else if ([value isKindOfClass:[NSNumber class]]) {
            NSNumber *numValue = (NSNumber *)value;
            if (strcmp(numValue.objCType, @encode(BOOL)) == 0 || numValue == @YES || numValue == @NO) {
                [yaml appendFormat:@"%@: %@\n", key, numValue.boolValue ? @"true" : @"false"];
            } else {
                [yaml appendFormat:@"%@: %@\n", key, numValue];
            }
        } else if ([value isKindOfClass:[NSNull class]]) {
            [yaml appendFormat:@"%@: null\n", key];
        } else {
            [yaml appendFormat:@"%@: %@\n", key, value];
        }
    }

    return [yaml copy];
}

- (void)handleApiDocs:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *docsPath = [cwd stringByAppendingPathComponent:@"ATProtoPDS/Sources/App/Explore/Assets/docs.html"];

    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:docsPath encoding:NSUTF8StringEncoding error:&error];

    if (error || !html) {
        [response setJsonBody:@{@"error": @"Failed to load docs", @"details": error.localizedDescription ?: @"Unknown error"}];
        return;
    }

    response.contentType = @"text/html; charset=utf-8";
    [response setBodyData:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleApiOpenapiSpec:(NSDictionary *)params response:(HttpResponse *)response {
    NSDictionary *spec = [self generateOpenAPISpec];
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:spec options:NSJSONWritingPrettyPrinted error:&jsonError];

    if (jsonError) {
        [response setJsonBody:@{@"error": @"Failed to generate OpenAPI spec", @"details": jsonError.localizedDescription ?: @"Unknown error"}];
        return;
    }

    NSString *yamlString = [self jsonToYAML:spec indent:0];

    NSString *format = params[@"format"];
    if ([format.lowercaseString isEqualToString:@"json"]) {
        response.contentType = @"application/json";
        [response setBodyData:jsonData];
    } else {
        response.contentType = @"application/yaml";
        [response setBodyData:[yamlString dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

@end
