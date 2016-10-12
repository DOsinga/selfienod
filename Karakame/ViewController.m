//
//  ViewController.m
//  Karakame
//
//  Created by Douwe Osinga on 9/27/16.
//  Copyright © 2016 Douwe Osinga. All rights reserved.
//

#import "ViewController.h"
#import "OpenCVBitmap.h"
#import "SettingsViewController.h"

@interface ViewController ()

@property(nonatomic, strong) NSMutableArray *faceRectangles;

@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@property(nonatomic, strong) UIView *cameraUiView;
@property(nonatomic, strong) AVCaptureDevice *inputDevice;
@property(nonatomic) int recentFaces;
@property(nonatomic) NSTimeInterval lastTimeNoFace;
@property(nonatomic) NSTimeInterval lastTimeAFace;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.faceRectangles = [NSMutableArray new];
    [self setupCaptureSession];
    [[UIApplication sharedApplication] setIdleTimerDisabled: TRUE];
}

- (AVCaptureVideoOrientation)orientationFromDevice {
    switch ([[UIDevice currentDevice] orientation]) {
        case UIDeviceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIDeviceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeLeft;
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

// Create and configure a capture session and start it running
- (void)setupCaptureSession {
    NSError *error = nil;

    // Create the session
    self.session = [[AVCaptureSession alloc] init];

    for(AVCaptureDevice *camera in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if([camera position] == AVCaptureDevicePositionFront) { // is front camera  
            self.inputDevice = camera;
            break;
        }
    }

    // Create a device input with the device and add it to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:self.inputDevice
                                                                        error:&error];
    [self.session addInput:input];

    self.session.sessionPreset = AVCaptureSessionPresetPhoto;

    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
    [self.stillImageOutput setOutputSettings:outputSettings];
    [self.session addOutput:self.stillImageOutput];

    // Create a VideoDataOutput and add it to the session
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    [self.session addOutput:output];

    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    [conn setVideoOrientation:[self orientationFromDevice]];

    // Specify the pixel format
    output.videoSettings = @{(id) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};

    if ([self.inputDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        [self.inputDevice lockForConfiguration:nil];
        [self.inputDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        [self.inputDevice unlockForConfiguration];
    }

    NSLog(@"Adding video preview layer");
    self.captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.captureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];


    //----- DISPLAY THE PREVIEW LAYER -----
    CGRect layerRect = [[[self view] layer] bounds];
    [self.captureVideoPreviewLayer setBounds:layerRect];
    [self.captureVideoPreviewLayer setPosition:CGPointMake(CGRectGetMidX(layerRect), CGRectGetMidY(layerRect))];
    self.cameraUiView = [[UIView alloc] init];
    [[self view] addSubview:self.cameraUiView];
    [self.view sendSubviewToBack:self.cameraUiView];
    [[self.cameraUiView layer] addSublayer:self.captureVideoPreviewLayer];

    UITapGestureRecognizer *singleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusGesture:)];
    [self.cameraUiView addGestureRecognizer:singleTapGestureRecognizer];


    //----- START THE CAPTURE SESSION RUNNING -----
    [self.session startRunning];

    // Configure your output.
    dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
    [output setSampleBufferDelegate:self queue:queue];
}

- (void)focusGesture:(id)focusGesture {
    if ([focusGesture isKindOfClass:[UITapGestureRecognizer class]]) {
        UITapGestureRecognizer *tap = focusGesture;
        if (tap.state == UIGestureRecognizerStateRecognized) {
            CGPoint location = [tap locationInView:self.cameraUiView];

            [self focusAtPoint:location];
        }
    }
}

- (void)focusAtPoint:(CGPoint)point {
    CGSize frameSize = self.cameraUiView.bounds.size;
    CGPoint pointOfInterest = CGPointMake(point.y / frameSize.height, 1.f - (point.x / frameSize.width));

    if ([self.inputDevice isFocusPointOfInterestSupported] && [self.inputDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {

        //Lock camera for configuration if possible
        NSError *error;
        if ([self.inputDevice lockForConfiguration:&error]) {

            if ([self.inputDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
                [self.inputDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
            }

            if ([self.inputDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                [self.inputDevice setFocusMode:AVCaptureFocusModeAutoFocus];
                [self.inputDevice setFocusPointOfInterest:pointOfInterest];
            }

            if([self.inputDevice isExposurePointOfInterestSupported] && [self.inputDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
                [self.inputDevice setExposurePointOfInterest:pointOfInterest];
                [self.inputDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }

            [self.inputDevice unlockForConfiguration];

        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIImage *)processImages:(NSMutableArray *)array {
    OpenCVBitmap *first = array[0];

    NSUInteger middleIndex = [array count] / 2;
    for (NSUInteger i = 0; i < [array count]; i++) {
        if (i != middleIndex) {
            [array[i] stablizeTo:array[middleIndex]];
        }
    }

    [first copyMedian:array];
    return [first toUIImage];
}

- (void)capturedSampleBuffer:(CMSampleBufferRef) imageSampleBuffer orientation:(AVCaptureVideoOrientation)orientation {
    NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
    UIImage *image = [[UIImage alloc] initWithData:imageData];
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(imageSaved:withError:andContext:), nil);
}

- (void)imageSaved:(UIImage *)image withError:(NSError *)error andContext:(void*)context {
    NSLog(@"Done: %@", error);
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    OpenCVBitmap *bm = [[OpenCVBitmap alloc] initWithSampleBuffer:sampleBuffer
                                                      orientation:[self orientationFromDevice]];
    NSArray *faces = [bm runDetector:@"haarcascade_frontalface_default"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.recentFaces = (self.recentFaces * 2) % 8;
        for (UIView *box in self.faceRectangles) {
            [box removeFromSuperview];
        }
        if ([faces count]) {
            self.recentFaces += 1;
            [self.faceRectangles removeAllObjects];
            for (NSValue *nds in faces) {
                CGRect rect = nds.CGRectValue;
                float xm = self.view.bounds.size.width / bm.width;
                float ym = self.view.bounds.size.height / bm.height;
                rect = CGRectMake(rect.origin.x * xm, rect.origin.y * ym,
                                  rect.size.width * xm, rect.size.height * ym
                );
                UIView *myBox  = [[UIView alloc] initWithFrame:rect];
                myBox.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
                myBox.layer.borderColor = [UIColor blackColor].CGColor;
                myBox.layer.borderWidth = 2;
                [self.faceRectangles addObject:myBox];
                [self.view addSubview:myBox];
            }
        }
        NSLog(@"faces: %d, interval:%2.2f", self.recentFaces, self.lastTimeNoFace - self.lastTimeAFace);
        if (self.recentFaces == 0) {
            self.lastTimeNoFace = [[NSDate date] timeIntervalSince1970];
        } else if (self.recentFaces > 6) {
            if (self.lastTimeNoFace > 0 && self.lastTimeAFace > 0) {
                double interval = self.lastTimeNoFace - self.lastTimeAFace;
                if (interval > 0.2 && interval < 0.8) {
                    [self captureStillImage];
                }
            }
            self.lastTimeAFace = [[NSDate date] timeIntervalSince1970];
        }
    });
}

- (void) captureStillImage {
    for (AVCaptureConnection *connection in self.stillImageOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:
                        ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
                            [self.self capturedSampleBuffer: imageSampleBuffer orientation:connection.videoOrientation];
                        }];
            }
        }
    }
}

- (void)takeAnotherImage:(id)takeAnotherImage {
    [self captureStillImage];
}

- (IBAction)unwindToList:(UIStoryboardSegue *)segue {
    
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
}


@end
