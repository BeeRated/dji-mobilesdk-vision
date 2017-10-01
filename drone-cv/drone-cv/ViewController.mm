//
//  ViewController.m
//  drone-cv
//
//  Created by Zhiyuan Li on 7/6/17.
//  Copyright © 2017 dji. All rights reserved.
//

#import <opencv2/opencv.hpp>
#import "ViewController.h"
#import <DJISDK/DJISDK.h>
#import <VideoPreviewer/VideoPreviewer.h>
#import "OpenCVConversion.h"
#import "DroneHelper.h"
#ifdef __cplusplus
  #include <vector>
  #include <opencv2/imgproc/imgproc.hpp>
  #include <opencv2/objdetect/objdetect.hpp>
  #include <opencv2/video/tracking.hpp>
#include <opencv2/imgcodecs/ios.h>
#include "MagicInAir.h"
using namespace std;
#endif

#define PHOTO_NUMBER 4
#define ROTATE_ANGLE 90

#define weakSelf(__TARGET__) __weak typeof(self) __TARGET__=self
#define weakReturn(__TARGET__) if(__TARGET__==nil)return;


@interface ViewController()<DJIVideoFeedListener, DJISDKManagerDelegate>
{
    SimpleFaceDetector* myFaceDetector;
}

@property (weak, nonatomic) IBOutlet UIView *viewLive;
@property (weak, nonatomic) IBOutlet UIImageView *viewProcessed;

@property (weak, nonatomic) IBOutlet UILabel *debug1;
@property (weak, nonatomic) IBOutlet UILabel *debug2;
@property (weak, nonatomic) IBOutlet UILabel *telemetry;

@property (weak, nonatomic) NSTimer *myTimer;

@property (nonatomic, copy, nullable) void (^processFrame)(UIImage *frame);
@property (nonatomic, copy) void (^defaultProcess)(UIImage *frame);

@property (strong, nonatomic) DroneHelper *spark;

@property (atomic) enum ImgProcess_Mode imgProcType;

// Buttons
@property (weak, nonatomic) IBOutlet UIButton *btnLaplace;
@property (weak, nonatomic) IBOutlet UIButton *btnBlur;
@property (weak, nonatomic) IBOutlet UIButton *btnFaceDetect;
@property (weak, nonatomic) IBOutlet UIButton *btnGimbal;
@property (weak, nonatomic) IBOutlet UIButton *btnTakeoffLand;
@property (weak, nonatomic) IBOutlet UIButton *btnMoveTest;
@property (weak, nonatomic) IBOutlet UIButton *btnArucoTag;

@property (atomic) double aircraftAltitude;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view, typically from a nib.
    [self registerApp];
    self.viewProcessed.contentMode = UIViewContentModeScaleAspectFit;
    [self.viewProcessed setBackgroundColor:[UIColor redColor]];
    
    UIImage *image = [UIImage imageNamed:@"mavic.jpg"];
    if(image != nil)
        self.viewProcessed.image = image;

    self.myTimer=nil;
    
    // We define the default frame processing function (block)
    // to be just add a "Default" label on the resized image
    self.defaultProcess = ^(UIImage *frame){
        cv::Mat colorImg = [OpenCVConversion cvMatFromUIImage:frame];
        if(colorImg.cols == 0) {
            NSLog(@"Invalid frame!");
            return;
        }
//        std::cout<<"\n wh"<<colorImg.cols<<"  "<<colorImg.rows;
        cv::resize(colorImg, colorImg, cv::Size(640, 360));
//        std::cout<<"\n wh"<<colorImg.cols<<"  "<<colorImg.rows;
        
        // The default image processing routine just put a text to the resized image
        putText(colorImg, "Default" , cv::Point(150, 40), 1, 4, cv::Scalar(255, 255, 255), 2, 8, 0);
        
        [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:colorImg]];
    };
    
    self.imgProcType = IMG_PROC_DEFAULT;

    myFaceDetector = new SimpleFaceDetector("lbpcascade_frontalface");
    self.spark = [[DroneHelper alloc] init];

}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self resetVideoPreview];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark App Register
- (void)registerApp
{
    //Please enter your App key in the "DJISDKAppKey" key in info.plist file.
    [DJISDKManager registerAppWithDelegate:self];
}

- (void)showAlertViewWithTitle:(NSString *)title withMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark DJISDKManagerDelegate Method
- (void)appRegisteredWithError:(NSError *)error
{
    NSString* message = @"Register:OK!";
    if (error) {
        message = [NSString stringWithFormat:@"Register:Failed. %@"];
    }
    
    self.debug1.text = message;
    NSLog(message);
    
    [DJISDKManager startConnectionToProduct];
    
    //Use the following line if you are debugging with bridge
    //[DJISDKManager enableBridgeModeWithBridgeAppIP:@"192.168.0.107"];
}

- (void)productConnected:(DJIBaseProduct* _Nullable)product
{
    if(product)
    {
        [self setupVideoPreviewer]; // Implemented below
        
        DJICamera * myCamera = [self fetchCamera];
        DJIGimbal * myGimbal = [self fetchGimbal];
        DJIFlightController * myFC = [self fetchFlightController];
        
        if(myCamera == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch camera"];
        }
        else if(myGimbal == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch gimbal"];
        }
        else if(myFC == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch FC"];
        }
        else{
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"All components fetched"];
            myFC.delegate = self.spark;
        }
    }
    else
    {
        [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Error!"];
    }
}

- (void) productDisconnected
{
    [self resetVideoPreview]; // Implemented below
}

#pragma mark Get Drone Components
- (DJICamera*) fetchCamera {
    if (![DJISDKManager product]) {
        return nil;
    }
    return [DJISDKManager product].camera;
}

- (DJIFlightController*) fetchFlightController {
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).flightController;
    }
    
    return nil;
}

- (DJIGimbal*) fetchGimbal {
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).gimbal;
    }
    else if ([[DJISDKManager product] isKindOfClass:[DJIHandheld class]]) {
        return ((DJIHandheld*)[DJISDKManager product]).gimbal;
    }
    
    return nil;
}


// Called by productConnected
- (void) setupVideoPreviewer
{
    self.debug1.text = @"Connected!";
    self.debug2.text = @"Init-ed";
    [[VideoPreviewer instance] setView:self.viewLive];
    [[DJISDKManager videoFeeder].primaryVideoFeed addListener:self withQueue:nil];
    [[VideoPreviewer instance] start];
    
    self.myTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                    target:self
                                                  selector:@selector(timerCallback)
                                                  userInfo:nil
                                                   repeats:YES];
    
    self.processFrame = self.defaultProcess;
}

// Called by productDisconnected
- (void) resetVideoPreview
{
    self.debug1.text = @"Disconnected!";
    [[VideoPreviewer instance] unSetView];
    [[DJISDKManager videoFeeder].primaryVideoFeed removeListener:self];
    [self.myTimer invalidate];
}

#pragma mark - DJIVideoFeedListener
-(void)videoFeed:(DJIVideoFeed *)videoFeed didUpdateVideoData:(NSData *)videoData {
    [[VideoPreviewer instance] push:(uint8_t *)videoData.bytes length:(int)videoData.length];
}
//
//- (void)takeSnapshot
//{
//    UIView *snapshot = [self.fpvPreview snapshotViewAfterScreenUpdates:YES];
//    snapshot.tag = 100001;
//    
//    if ([self.imgView viewWithTag:100001]) {
//        [[self.imgView viewWithTag:100001] removeFromSuperview];
//    }
//    
//    [self.imgView addSubview:snapshot];
//    self.debug2.text = [NSString stringWithFormat:@"%d", self.counter++];
//}

-(void) timerCallback
{
    [[VideoPreviewer instance] snapshotPreview:self.processFrame];
    self.telemetry.text = [NSString stringWithFormat:@"h=%.2f\n\
                                                       vx=%.2f\n\
                                                       vy=%.2f\n\
                                                       vz=%.2f\n\
                                                       yaw=%.2f\n\
                                                       pitch=%.2f\
                                                       roll=%.2f",
                           self.spark.heightAboveHome,
                           self.spark.NEDVelocityX, self.spark.NEDVelocityY, self.spark.NEDVelocityZ,
                           self.spark.yaw, self.spark.pitch, self.spark.roll];
}

// Filter Buttons
- (IBAction)doLaplace:(id)sender;
{
    if(self.imgProcType == IMG_PROC_LAPLACIAN)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_LAPLACIAN;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(480, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            filterLaplace(grayImg, 3);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
        };
        self.debug2.text = @"Laplace";
    }
}

- (IBAction)doGaussian:(id)sender;
{
    if(self.imgProcType == IMG_PROC_BLUR_GAUSSIAN)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_BLUR_GAUSSIAN;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(480, 360));

            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            filterBlurHomogeneousAccelerated(grayImg, 21);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
        };
        self.debug2.text = @"Blur";
    }
}

//-(void) detect(cv::Mat &img, cv::CascadeClassifier &detectorBody)
//{
//    vector<cv::Rect> human;
//    cvtColor(img, img, CV_BGR2GRAY);
//
//    detectorBody.detectMultiScale(img, human, 1.1, 2, 0 | 1, cv::Size(40,70), cv::Size(80, 300));
//    // Draw results from detectorBody into original colored image
//    if (human.size() > 0) {
//        for (int gg = 0; gg < human.size(); gg++) {
//            cv::rectangle(img, human[gg].tl(), human[gg].br(), Scalar(0,0,255), 2, 8, 0);
//        }
//    }
//}

- (IBAction)doDetectFace:(id)sender;
{
    if(self.imgProcType == IMG_PROC_FACE_DETECT)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_FACE_DETECT;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(640, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            NSInteger f = myFaceDetector->detectFaceInMat(grayImg);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
            self.debug2.text = [NSString stringWithFormat:@"%d faces", f];
        };
    }
}

- (IBAction)doDetectAR:(id)sender
{
    //[self enableVS];
    [self.spark enterVirtualStickMode];
    [self.spark setVerticleModeToAbsoluteHeight];
    static int goal_id = 1;
    enum {IN_AIR, ON_GROUND};
    static int detect_state  = IN_AIR;
    static int counter= 0;
    static bool yaw_mode = false;

    if(self.imgProcType == IMG_PROC_USER_1)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_USER_1;
        self.processFrame =
        ^(UIImage *frame){
            counter = counter+1;
            DroneHelper *spark_ptr = [self spark];
            DJIFlightController *flightController = [self fetchFlightController];
            
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(640, 360));
            //calibrate
            if(counter%10 == 0 && false)
            {
//                cv::imwrite( "image_meri_hai.jpg", grayImg );
                UIImage* Im2save = [OpenCVConversion UIImageFromCVMat:grayImg];
                UIImageWriteToSavedPhotosAlbum(Im2save,nil,nil, nil);
//                UIImageWriteToSavedPhotosAlbum(Im2save,self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil);
            }
            std::vector<std::vector<cv::Point2f> > corners;
            std::vector<int> detected_marker_IDs = detectARTagIDs(corners,grayImg);
            NSInteger n = detected_marker_IDs.size();
            
            // print the indices found
            std::vector<int> indices_found;
            
            //<TESTING INTRISICS>
            if(n>0)
            {
                std::vector<cv::Point3f> objectPoints;
                cv::Point3f p1,p2,p3,p4;
                p1.x = 0;   p1.y=0; p1.z=0;
                p2.x = .10;  p2.y=0; p2.z=0;
                p3.x = .10;  p3.y=.10;p3.z=0;
                p4.x = 0;   p4.y=.10;p4.z=0;
                objectPoints.push_back(p1);objectPoints.push_back(p2);objectPoints.push_back(p3);objectPoints.push_back(p4);
                std::vector<cv::Point2f> detectedCorners = corners[0];
                cv::Mat cameraMatrix;
                cv::Vec4f distCoeff;
                cameraMatrix = cv::Mat::zeros(3, 3, CV_32F);
                cameraMatrix.at<float>(0,0) = 633.4373;
                cameraMatrix.at<float>(0,2) = 328.3448;
                cameraMatrix.at<float>(1,1) = 636.4243;
                cameraMatrix.at<float>(1,2) = 186.8022;
                cameraMatrix.at<float>(2,2) = 1.0;
            
                distCoeff.zeros();
            
                cv::Mat rvec(3,3,CV_32F);
                cv::Mat tvec(3,1,CV_32F);
//                std::cout<<"corners:"<<detectedCorners.size()<<" Object:"<<objectPoints.size()<<cameraMatrix;
                cv::solvePnP(objectPoints,detectedCorners,cameraMatrix,distCoeff,rvec,tvec);
                cv::transpose(tvec, tvec);
                cv::Rodrigues(rvec, rvec);
                cv::Mat u,l;
                cv::Vec3d rpy = cv::RQDecomp3x3(rvec, u, l);
                std::cout<<"\nTvec: "<<tvec;
                std::cout<<"\nRPY: "<<rpy;
                
                
            //Trying to center
                cv::Point3f tag_frame; tag_frame.x = tvec.at<double>(0);
                tag_frame.y = tvec.at<double>(1);
                 tag_frame.z = tvec.at<double>(2);
                cv::Point3f tag_pos = TagFrame2DroneFrame(tag_frame);
                cv::Point3f target_pos(1.2,0,0);
                float tag_yaw = rpy[1];
                float yaw_rate_output;
                cv::Point3f motion_vector = TagPos2Control(tag_pos, target_pos, tag_yaw, yaw_rate_output);
                std::cout<< "\n Tag::"<<tag_frame.x<<"::"<<tag_frame.y<<"::"<<tag_frame.z<<"\n";
                std::cout<<"Transformed Tag::"<<tag_pos.x<<"::"<<tag_pos.y<<"::"<<tag_pos.z<<"::"<<tag_yaw<<"\n";
                std::cout<<"Motion Vector::"<<motion_vector.x<<"::"<<motion_vector.y<<"::"<<yaw_rate_output<<"\n";
                //int MINIMUM_DIST_PIXELS = 900;
                float yaw = 0;
                if(goal_achieved3d(target_pos, tag_pos) && goal_achieved_yaw(tag_yaw)){
                    Land(spark_ptr);
                }
                else{
                    Move(flightController, motion_vector.x, motion_vector.y, yaw_rate_output, 1.5);
                }
            }
            else{
                    Move(flightController, 0, 0, 20, 1.5);
                }
            
            //Move(flightController, 0, 0, 20, 1);
            // <TESTING INTRINSICS/>
            
            if(0){
                static const int marker_waypt[] = {20, 19, 32, 13, 12, 34, 01, 30, 31, 05, 26, 03, 33, 18, 22, 27, 23, 21, 16, 10};
                //std::vector<int> marker_waypt_indices(bla, bla+sizeof(bla)/sizeof(bla[0]));
                // find the indices of the aruco tags in marker_waypt_indices being detected
            
                bool found_goal_id = false;
                int goal_index_detect = 0;
                for(auto i=0; i<n; i++)
                {
                    if(detected_marker_IDs[i]==marker_waypt[goal_id]){
                    found_goal_id = true;
                    goal_index_detect = i;
                    break;
                }
                }
            
                cv::Point2f motion_vector(0,0);
                cv::Point2f marker_center(0,0);
                if(found_goal_id)
                {
                    marker_center = VectorAverage(corners[goal_index_detect]);
                    cv::Point2f image_vector = marker_center - cv::Point2f(240,180);
                    motion_vector = convertImageVectorToMotionVector(image_vector);
                }
                //std::cout<<"Moving By::"<<motion_vector<<" Moving to::"<<marker_waypt[goal_id]<<"\n";
                //std::cout<<"Waypoint num::"<<goal_id;
                Move(flightController, motion_vector.x, motion_vector.y, 0, 3);
                if(goal_achieved(marker_center) && found_goal_id)
                {
                    goal_id = goal_id+1;
                    //goal_id = std::min(goal_id+1,marker_waypt_indices.size()-1);
                    if(goal_id <= 19)
                        goal_id = goal_id;
                    else
                        goal_id = 0;
                }
            }
            
            
            PitchGimbal(spark_ptr,0.0);
            
            // TAKEOFF
            //TakeOff(spark_ptr);

            //LAND
            //Land(spark_ptr);
            
            //if(counter<100)
            //if((image_vector.x*image_vector.x + image_vector.y*image_vector.y)<900)
            //   Move(flightController, motion_vector.x, motion_vector.y, 0, 3);
            //else
            //Move(flightController, motion_vector.x, motion_vector.y, 0, 3);
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
            self.debug2.text = [NSString stringWithFormat:@"%d Tags", n];
        };
    }
}

/**
 Demo how to move the gimbal to face forward and down.
 */
- (IBAction)onGimbalButtonClicked:(id)sender;
{
    enum {FORWARD=0, DOWN=1};
    static int action = FORWARD;
    
    if(action == FORWARD)
    {
        if([self.spark setGimbalPitchDegree: 0.0] == FALSE) {
            [self showAlertViewWithTitle:@"Move Gimbal" withMessage:@"Failed"];
        }
        action = DOWN;
    }
    else
    {
        if([self.spark setGimbalPitchDegree: -65.0] == FALSE) {
            [self showAlertViewWithTitle:@"Move Gimbal" withMessage:@"Failed"];
        }
        action = FORWARD;
    }
}

/**
 Demo how to take off and land.
 */
- (IBAction)onTakeoffButtonClicked:(id)sender
{
    enum {TAKEOFF=0, LAND=1};
    static int action = TAKEOFF;
    
    if(action == TAKEOFF)
    {
        if([self.spark takeoff] == FALSE) {
            [self showAlertViewWithTitle:@"Takeoff" withMessage:@"Failed"];
        }
        else {
            [self showAlertViewWithTitle:@"Takeoff" withMessage:@"Succeeded"];
        }
        [self.btnTakeoffLand setTitle:@"Land" forState:UIControlStateNormal];
        action = LAND;
    }
    else
    {
        if([self.spark land] == FALSE) {
            [self showAlertViewWithTitle:@"Land" withMessage:@"Failed"];
        }
        else {
            [self showAlertViewWithTitle:@"Land" withMessage:@"Succeeded"];
        }
        
        [self.btnTakeoffLand setTitle:@"Takeoff" forState:UIControlStateNormal];
        action = TAKEOFF;
    }
}

- (IBAction)onDroneMoveClicked:(id)sender
{
    if(self.imgProcType == IMG_PROC_USER_2)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_USER_2;
        [self.spark enterVirtualStickMode];
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat colorImg = [OpenCVConversion cvMatFromUIImage:frame];
            if(colorImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(colorImg, colorImg, cv::Size(480, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            sampleFeedback(colorImg, self.spark);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:colorImg]];
            //self.debug2.text = [NSString stringWithFormat:@"%d Tags", n];
        };
    }
}

//- (IBAction)onDroneMoveClicked:(id)sender
//{
//    [self enableVS];
//    
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        [self executeVirtualStickControl];
//    });
//}
//
- (void) enableVS
{
    // disable gesture mode
    if([[DJISDKManager product].model isEqual: DJIAircraftModelNameSpark])
    {
        [[DJISDKManager missionControl].activeTrackMissionOperator setGestureModeEnabled:NO withCompletion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Set Gesture mode enabled failed");
            }
            else {
                NSLog(@"Set Gesture mode enabled Succeeded");
            }
        }];
    }

    // Enter the virtual stick mode with some default settings
    DJIFlightController *fc = [self fetchFlightController];
    //fc.yawControlMode = DJIVirtualStickYawControlModeAngle;
    fc.yawControlMode =DJIVirtualStickYawControlModeAngularVelocity;
    fc.rollPitchControlMode = DJIVirtualStickRollPitchControlModeVelocity;
    fc.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystemBody;
    //DJIVirtualStickFlightCoordinateSystemBody;
    [fc setVirtualStickModeEnabled:YES withCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Enable VirtualStickControlMode Failed");
        }
        else {
            NSLog(@"Enable VirtualStickControlMode Succeeded");
        }
    }];

}

//
//- (void)executeVirtualStickControl
//{
//    __weak DJICamera *camera = [self fetchCamera];
//    
//    for(int i = 0;i < PHOTO_NUMBER; i++){
//        
//        float yawAngle = ROTATE_ANGLE*i;
//        NSLog(@"Yaw angle=%f", yawAngle);
//        if (yawAngle > 180.0) { //Filter the angle between -180 ~ 0, 0 ~ 180
//            yawAngle = yawAngle - 360;
//        }
//        
//        NSTimer *timer =  [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(rotateDrone:) userInfo:@{@"YawAngle":@(yawAngle)} repeats:YES];
//        [timer fire];
//        
//        [[NSRunLoop currentRunLoop]addTimer:timer forMode:NSDefaultRunLoopMode];
//        [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
//        
//        [timer invalidate];
//        timer = nil;
//        
//        sleep(2);
//    }
//    
//    DJIFlightController *flightController = [self fetchFlightController];
//    [flightController setVirtualStickModeEnabled:NO withCompletion:^(NSError * _Nullable error) {
//        if (error) {
//            NSLog(@"Disable VirtualStickControlMode Failed");
//            DJIFlightController *flightController = [self fetchFlightController];
//            [flightController setVirtualStickModeEnabled:NO withCompletion:nil];
//        }
//    }];
//    
//    weakSelf(target);
//    dispatch_async(dispatch_get_main_queue(), ^{
//        weakReturn(target);
//        [target showAlertViewWithTitle:@"Capture Photos" withMessage:@"Capture finished"];
//    });
//}
//
//- (void)rotateDrone:(NSTimer *)timer
//{
//    NSDictionary *dict = [timer userInfo];
//    float yawAngle = [[dict objectForKey:@"YawAngle"] floatValue];
//    
//    DJIFlightController *flightController = [self fetchFlightController];
//    
//    DJIVirtualStickFlightControlData vsFlightCtrlData;
//    vsFlightCtrlData.pitch = 0;
//    vsFlightCtrlData.roll = 0;
//    vsFlightCtrlData.verticalThrottle = 0;
//    vsFlightCtrlData.yaw = yawAngle;
//    
//    flightController.isVirtualStickAdvancedModeEnabled = YES;
//    
//    [flightController sendVirtualStickFlightControlData:vsFlightCtrlData withCompletion:^(NSError * _Nullable error) {
//        if (error) {
//            NSLog(@"Send FlightControl Data Failed %@", error.description);
//        }
//    }];
//    
//}

@end
