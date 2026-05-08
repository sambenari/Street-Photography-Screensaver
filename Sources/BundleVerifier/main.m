#import <Foundation/Foundation.h>
#import <ScreenSaver/ScreenSaver.h>

static void Fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            Fail(@"Usage: BundleVerifier /path/to/ScreenSaver.saver");
        }

        NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        if (!bundle) {
            Fail([NSString stringWithFormat:@"Could not create bundle at %@", bundlePath]);
        }

        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            Fail([NSString stringWithFormat:@"Could not load bundle: %@", error.localizedDescription]);
        }

        Class principalClass = bundle.principalClass;
        if (!principalClass) {
            Fail(@"Bundle does not declare a principal class.");
        }

        if (![principalClass isSubclassOfClass:ScreenSaverView.class]) {
            Fail([NSString stringWithFormat:@"%@ is not a ScreenSaverView subclass.", NSStringFromClass(principalClass)]);
        }

        ScreenSaverView *view = [[principalClass alloc] initWithFrame:NSMakeRect(0, 0, 800, 600) isPreview:NO];
        if (!view) {
            Fail(@"Principal class could not instantiate as a screen saver view.");
        }
        [view animateOneFrame];

        NSArray *imageURLs = nil;
        @try {
            imageURLs = [view valueForKey:@"imageURLs"];
        } @catch (NSException *exception) {
            imageURLs = nil;
        }

        printf("Loaded %s; principal class %s instantiated and animated as a ScreenSaverView; cached image URLs: %lu.\n", bundlePath.UTF8String, NSStringFromClass(principalClass).UTF8String, (unsigned long)imageURLs.count);
    }
    return 0;
}
