#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

// Objective-C camera capture with no NSCameraUsageDescription in Info.plist.
// The 5.1.1 purpose-string check must fire on ObjC sources too.
@interface CameraViewController : UIViewController
@end

@implementation CameraViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  [session startRunning];
}

@end
