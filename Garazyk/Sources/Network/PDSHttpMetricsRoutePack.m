#import "Network/PDSHttpMetricsRoutePack.h"

#import "Metrics/PDSMetrics.h"
#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpMetricsRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server {
  [server addRoute:@"GET"
              path:@"/metrics"
           handler:^(HttpRequest *request, HttpResponse *response) {
             response.statusCode = HttpStatusOK;
             [response setHeader:@"text/plain; version=0.0.4; charset=utf-8"
                          forKey:@"Content-Type"];
             [response setBodyString:[[PDSMetrics sharedMetrics] exportPrometheus]];
           }];

  PDS_LOG_DEBUG(@"PDSHttpMetricsRoutePack: Metrics endpoint registered");
}

@end
