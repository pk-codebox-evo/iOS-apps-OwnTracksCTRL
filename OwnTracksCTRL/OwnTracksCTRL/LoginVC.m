//
//  LoginViewController.m
//  OwnTracksCTRL
//
//  Created by Christoph Krey on 24.10.14.
//  Copyright (c) 2014 OwnTracks. All rights reserved.
//

#import "LoginVC.h"
#import "AppDelegate.h"
#import "Vehicle+Create.h"

#ifndef CTRLTV
#import <CocoaLumberjack/CocoaLumberjack.h>
#else
#define DDLogVerbose NSLog
#endif

@interface LoginVC ()
@property (weak, nonatomic) IBOutlet UITextField *UIuser;
@property (weak, nonatomic) IBOutlet UITextField *UIpassword;
@property (weak, nonatomic) IBOutlet UIButton *UILookup;

@property (strong, nonatomic) NSURLSession *urlSession;
@property (strong, nonatomic) NSURLSessionDownloadTask *downloadTask;

@property (nonatomic) BOOL autostart;

@end

@implementation LoginVC

#ifndef CTRLTV
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#endif

- (void)loadView {
    [super loadView];
    self.autostart = true;
}

- (void)automaticStart {
    self.autostart = true;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updated];
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate addObserver:self forKeyPath:@"token"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:nil];
    [self.navigationController.navigationBar setHidden:TRUE];
    [appDelegate disconnect];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self updateValues];
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate removeObserver:self
                     forKeyPath:@"token"
                        context:nil];
    [appDelegate saveContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"token"]) {
        if ([object valueForKey:keyPath]) {
            if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive
                || [UIApplication sharedApplication].applicationState == UIApplicationStateInactive) {
                if (self.autostart) {
                    [self lookup:nil];
                }
            }
        }
    }
}

- (void)updateValues {
    AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    
    if (self.UIuser) delegate.confD.user = self.UIuser.text;
    if (self.UIpassword) delegate.confD.passwd = self.UIpassword.text;
}

- (void)updated {
    AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    
    self.UIuser.text = delegate.confD.user;
    self.UIpassword.text = delegate.confD.passwd;
}

- (IBAction)touchedOutsideText:(UITapGestureRecognizer *)sender {
    [self updateValues];
    [self.UIuser resignFirstResponder];
    [self.UIpassword resignFirstResponder];
}

- (IBAction)changedUser:(UITextField *)sender {
    [Vehicle trash];
    AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    [delegate.managedObjectContext deleteObject:delegate.broker];
    delegate.broker = [Broker brokerInManagedObjectContext:delegate.managedObjectContext];
    [delegate saveContext];
}

- (IBAction)lookup:(UIButton *)sender {
    self.autostart = false;
    if (self.downloadTask) {
        [self.downloadTask cancel];
    }

    [self updateValues];
    AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    
    NSString *tokenPost = @"";
    if (delegate.token && delegate.token.length > 0) {
        tokenPost = [NSString stringWithFormat:@"&token=%@", delegate.token];
    }
    
    NSUUID *uuid = [[UIDevice currentDevice] identifierForVendor];
    
    NSString *uuidString = [uuid.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    DDLogVerbose(@"uuidString=%@", uuidString);
    
    NSString *post = [NSString stringWithFormat:@"username=%@&password=%@%@&clientid=%@",
                      delegate.confD.user,
                      delegate.confD.passwd,
                      tokenPost,
                      uuidString];
    
    DDLogVerbose(@"post=%@", post);
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];

    NSString *postLength = [NSString stringWithFormat:@"%ld",(unsigned long)[postData length]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    
    NSString *urlString = [[NSUserDefaults standardUserDefaults] stringForKey:@"ctrldurl"];
    DDLogVerbose(@"urlString=%@", urlString);
    
    [request setURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    self.urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    self.downloadTask =
    [self.urlSession downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {

        DDLogVerbose(@"downloadTaskWithRequest completionhandler %@ %@ %@", location, response, error);
#ifndef CTRLTV
        [UIApplication sharedApplication].networkActivityIndicatorVisible = false;
#endif
        if (error) {
#ifndef CTRLTV
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Loading failed"
                                                                message:[error description]
                                                               delegate:nil
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:@"OK", nil];
            [alertView show];
#endif
        } else {
            NSDictionary *dictionary = nil;
            NSData *data = nil;
            if (location) {
                data = [NSData dataWithContentsOfURL:location];
            }
            if (data) {
                NSError *error;
                dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            }
            if (dictionary && [dictionary[@"_type"] isEqualToString:@"configuration"]) {
                DDLogVerbose(@"configuration %@", dictionary);
                AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;

                delegate.broker.host = [self stringFromJSON:dictionary key:@"host"];
                delegate.broker.port = [self numberFromJSON:dictionary key:@"port"];
                delegate.broker.auth = [self numberFromJSON:dictionary key:@"auth"];
                delegate.broker.tls = [self numberFromJSON:dictionary key:@"tls"];
                delegate.broker.user = [self stringFromJSON:dictionary key:@"username"];
                delegate.broker.passwd = [self stringFromJSON:dictionary key:@"password"];
                delegate.broker.trackurl = [self stringFromJSON:dictionary key:@"trackurl"];
                delegate.broker.certurl = [self stringFromJSON:dictionary key:@"certurl"];

                NSString *base = @"";
                for (NSString *topic in [self arrayFromJSON:dictionary key:@"topicList"]) {
                    if (base.length) {
                        base = [base stringByAppendingString:@" "];
                    }
                    base = [base stringByAppendingString:topic];
                }
                delegate.broker.base = base;

                delegate.broker.clientid = [self stringFromJSON:dictionary key:@"clientid"];
                [self updated];
                [self performSelectorOnMainThread:@selector(login) withObject:nil waitUntilDone:NO];
            } else {
                NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (dictionary) {
                    if ([dictionary[@"message"] isKindOfClass:[NSString class]]) {
                        message = dictionary[@"message"];
                    }
                }
#ifndef CTRLTV
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Settings invalid"
                                                                    message:message
                                                                   delegate:nil
                                                          cancelButtonTitle:nil
                                                          otherButtonTitles:@"OK", nil];
                [alertView show];
#endif
            }

        }

        self.downloadTask = nil;
        self.urlSession = nil;
    }];

    [self.downloadTask resume];
#ifndef CTRLTV
    [UIApplication sharedApplication].networkActivityIndicatorVisible = true;
#endif
}

- (void)login {
    [self performSegueWithIdentifier:@"Login" sender:nil];
}

- (IBAction)direct:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self performSegueWithIdentifier:@"Settings" sender:nil];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Login"]) {
        AppDelegate *delegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        [delegate connect];
    }
}

- (NSString *)stringFromJSON:(NSDictionary *)dictionary key:(NSString *)key {
    NSString *string = nil;
    
    id object = [dictionary objectForKey:key];
    if (object) {
        if ([object isKindOfClass:[NSString class]]) {
            string = (NSString *)object;
        }
    }
    return string;
}

- (NSNumber *)numberFromJSON:(NSDictionary *)dictionary key:(NSString *)key {
    NSNumber *number = nil;
    
    id object = [dictionary objectForKey:key];
    if (object) {
        if ([object isKindOfClass:[NSNumber class]]) {
            number = (NSNumber *)object;
        }
    }
    return number;
}

- (NSArray *)arrayFromJSON:(NSDictionary *)dictionary key:(NSString *)key {
    NSArray *array = nil;
    
    id object = [dictionary objectForKey:key];
    if (object) {
        if ([object isKindOfClass:[NSArray class]]) {
            array = (NSArray *)object;
        }
    }
    return array;
}

@end
