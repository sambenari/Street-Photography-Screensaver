#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

static NSString *AlbumName(void) {
    if (NSProcessInfo.processInfo.arguments.count > 1) {
        return NSProcessInfo.processInfo.arguments[1];
    }
    return @"Street Photography";
}

static void Fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

static void VerifyAlbum(NSString *albumName) {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.predicate = [NSPredicate predicateWithFormat:@"localizedTitle == %@", albumName];

    PHFetchResult<PHAssetCollection *> *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    PHFetchResult<PHAssetCollection *> *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    PHAssetCollection *album = userAlbums.firstObject ?: smartAlbums.firstObject;

    if (!album) {
        Fail([NSString stringWithFormat:@"Album \"%@\" was not found.", albumName]);
    }

    PHFetchOptions *assetOptions = [[PHFetchOptions alloc] init];
    assetOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsInAssetCollection:album options:assetOptions];

    printf("Album \"%s\" found with %lu image(s).\n", albumName.UTF8String, (unsigned long)assets.count);
    exit(assets.count > 0 ? 0 : 2);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *albumName = AlbumName();
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];

        switch (status) {
            case PHAuthorizationStatusAuthorized:
            case PHAuthorizationStatusLimited:
                VerifyAlbum(albumName);
                break;
            case PHAuthorizationStatusNotDetermined: {
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus requestStatus) {
                    if (requestStatus == PHAuthorizationStatusAuthorized || requestStatus == PHAuthorizationStatusLimited) {
                        VerifyAlbum(albumName);
                    } else {
                        Fail(@"Photos access was not granted.");
                    }
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                break;
            }
            case PHAuthorizationStatusDenied:
            case PHAuthorizationStatusRestricted:
                Fail(@"Photos access is denied. Enable it in System Settings > Privacy & Security > Photos.");
                break;
            default:
                Fail(@"Photos access is unavailable.");
                break;
        }
    }
    return 0;
}
