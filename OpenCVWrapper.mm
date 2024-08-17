#import "opencv2/opencv.hpp"
#import "opencv2/imgcodecs/ios.h"
#import "OpenCVWrapper.h"
#import <ARKit/ARKit.h>
#import <SceneKit/SceneKit.h>

// Add a method convertToMat to UIImage class
@interface UIImage (OpenCVWrapper)
- (void)convertToMat:(cv::Mat *)pMat alphaExists:(BOOL)alphaExists;
@end

@implementation UIImage (OpenCVWrapper)
- (void)convertToMat:(cv::Mat *)pMat alphaExists:(BOOL)alphaExists {
    cv::Mat mat;
    UIImageToMat(self, mat, alphaExists);

    if (self.imageOrientation == UIImageOrientationRight) {
        cv::rotate(mat, *pMat, cv::ROTATE_90_CLOCKWISE);
    } else if (self.imageOrientation == UIImageOrientationLeft) {
        cv::rotate(mat, *pMat, cv::ROTATE_90_COUNTERCLOCKWISE);
    } else if (self.imageOrientation == UIImageOrientationDown) {
        cv::rotate(mat, *pMat, cv::ROTATE_180);
    } else {
        mat.copyTo(*pMat);
    }
}
@end

@implementation OpenCVWrapper

+ (UIImage *)grayscaleImg:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:false];
    cv::Mat gray;

    if (mat.channels() > 1) {
        cv::cvtColor(mat, gray, cv::COLOR_RGB2GRAY);
    } else {
        mat.copyTo(gray);
    }

    UIImage *grayImg = MatToUIImage(gray);
    return grayImg;
}

+ (UIImage *)processImage:(UIImage *)image {
    cv::Mat mat;
    UIImageToMat(image, mat);

    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);

    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);  // Adjusted thresholds for more visible edges

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(edges, contours, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);

    cv::Mat contourOutput = mat.clone();
    cv::drawContours(contourOutput, contours, -1, cv::Scalar(255, 0, 0), 2);

    UIImage *resultImage = MatToUIImage(contourOutput);
    return resultImage;
}

+ (UIImage *)edgeDetection:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:true];  // alphaExists is true for 4-channel images

    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);

    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);  // Adjusted thresholds for more visible edges

    // Blur the edges to make them thicker and more visible
    cv::Mat blurredEdges;
    cv::blur(edges, blurredEdges, cv::Size(5, 5));

    // Dilate edges to make them thicker
    cv::Mat dilatedEdges;
    cv::dilate(blurredEdges, dilatedEdges, cv::Mat(), cv::Point(-1, -1), 3); // Increase the dilation iterations for thicker lines

    // Create a red-colored edge mask
    cv::Mat redEdges = cv::Mat::zeros(dilatedEdges.size(), CV_8UC4);
    std::vector<cv::Mat> channels = {dilatedEdges, cv::Mat::zeros(dilatedEdges.size(), CV_8UC1), cv::Mat::zeros(dilatedEdges.size(), CV_8UC1), cv::Mat::ones(dilatedEdges.size(), CV_8UC1) * 255};  // Set alpha to 255 for full opacity
    cv::merge(channels, redEdges);

    // Ensure redEdges have the same size and number of channels as the original image
    if (redEdges.size() != mat.size() || redEdges.channels() != mat.channels()) {
        NSLog(@"Resizing and converting redEdges to match the original image size and channels.");
        cv::resize(redEdges, redEdges, mat.size());
        if (mat.channels() == 4) {
            cv::cvtColor(redEdges, redEdges, cv::COLOR_BGR2BGRA);
        } else {
            cv::cvtColor(redEdges, redEdges, cv::COLOR_BGR2RGB);
        }
    }

    // Combine the red edges with the original image, ensuring the edges are fully opaque
    cv::Mat blended = mat.clone();
    for (int y = 0; y < redEdges.rows; ++y) {
        for (int x = 0; x < redEdges.cols; ++x) {
            if (redEdges.at<cv::Vec4b>(y, x)[0] > 0) {
                blended.at<cv::Vec4b>(y, x) = redEdges.at<cv::Vec4b>(y, x);
            }
        }
    }

    UIImage *edgeOverlayImage = MatToUIImage(blended);
    return edgeOverlayImage;
}

+ (UIImage *)contourOnly:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:true];

    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);

    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);

    // Blur the edges to make them thicker and more visible
    cv::Mat blurredEdges;
    cv::blur(edges, blurredEdges, cv::Size(5, 5));

    // Dilate edges to make them thicker
    cv::Mat dilatedEdges;
    cv::dilate(blurredEdges, dilatedEdges, cv::Mat(), cv::Point(-1, -1), 3); // Increase the dilation iterations for thicker lines

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(dilatedEdges, contours, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);

    // Create a black image with white contours
    cv::Mat contourImage = cv::Mat::zeros(dilatedEdges.size(), CV_8UC1);
    cv::drawContours(contourImage, contours, -1, cv::Scalar(255), 2);

    UIImage *resultImage = MatToUIImage(contourImage);
    return resultImage;
}

bool isShape(const std::vector<cv::Point>& approx, int sides, double cosineThreshold, double minArea) {
    if (approx.size() != sides) return false;

    double cosines[sides];
    for (int i = 0; i < sides; i++) {
        cv::Point2f pt1 = approx[i];
        cv::Point2f pt2 = approx[(i+1) % sides];
        cv::Point2f pt0 = approx[(i+3) % sides];
        cv::Point2f d1 = pt1 - pt0;
        cv::Point2f d2 = pt2 - pt1;
        double cosine = (d1.x * d2.x + d1.y * d2.y) / (cv::norm(d1) * cv::norm(d2));
        cosines[i] = cosine;
    }

    // Check if all cosines are within the specified threshold
    for (double cosine : cosines) {
        if (std::abs(cosine) > cosineThreshold) {
            return false;
        }
    }

    // Check if the area is greater than the minimum area
    double area = cv::contourArea(approx);
    if (area < minArea) {
        return false;
    }

    return true;
}



+ (UIImage *)detectShapes:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:true];
    
    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);

    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);

    cv::Mat blurredEdges;
    cv::blur(edges, blurredEdges, cv::Size(5, 5));

    cv::Mat dilatedEdges;
    cv::dilate(blurredEdges, dilatedEdges, cv::Mat(), cv::Point(-1, -1), 3);

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(dilatedEdges, contours, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);

    cv::Mat result = cv::Mat::zeros(mat.size(), CV_8UC3);

    double cosineThreshold = 0.2;
    double minArea = 1000.0;
    double minCircularity = 0.8;

    for (const auto& contour : contours) {
        std::vector<cv::Point2f> contour2f;
        cv::Mat(contour).convertTo(contour2f, CV_32F);
        std::vector<cv::Point2f> approx;
        cv::approxPolyDP(contour2f, approx, cv::arcLength(contour2f, true) * 0.02, true);
        
        

        if (approx.size() == 4) {
            std::vector<cv::Point> approxPoints(approx.begin(), approx.end());
            if (isShape(approxPoints, approx.size(), cosineThreshold, minArea)) {
                cv::Scalar color = cv::Scalar(0, 0, 255);
                cv::polylines(result, approxPoints, true, color, 2);
            }
        } else  if (approx.size() >= 5 && approx.size() <= 8) {
            std::vector<cv::Point> approxPoints(approx.begin(), approx.end());
            if (isShape(approxPoints, approx.size(), cosineThreshold, minArea)) {
                cv::Scalar color = cv::Scalar(255, 0, 0); 
                cv::polylines(result, approxPoints, true, color, 2);
            }
        }
    }

    UIImage *resultImage = MatToUIImage(result);
    return resultImage;
}

+ (NSDictionary *)detectShapes2:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:true];
    
    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);
    
    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);
    
    // Blur the edges to make them thicker and more visible
    cv::Mat blurredEdges;
    cv::blur(edges, blurredEdges, cv::Size(5, 5));
    
    // Dilate edges to make them thicker
    cv::Mat dilatedEdges;
    cv::dilate(blurredEdges, dilatedEdges, cv::Mat(), cv::Point(-1, -1), 3);
    
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(dilatedEdges, contours, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);
    
    cv::Mat result = mat.clone(); // Clone the original image to keep it intact for drawing
    
    double cosineThreshold = 0.3; // Relaxed threshold
    double minArea = 500.0;       // Smaller minimum area

    // Define the minimum width and height for bounding boxes
    CGFloat minWidth = 30.0;
    CGFloat minHeight = 50.0;
    
    NSMutableArray *normalizedBoundingBoxes = [NSMutableArray array];
    
    CGSize imageSize = image.size;
    
    for (const auto& contour : contours) {
        std::vector<cv::Point2f> contour2f;
        cv::Mat(contour).convertTo(contour2f, CV_32F);
        std::vector<cv::Point2f> approx;
        cv::approxPolyDP(contour2f, approx, cv::arcLength(contour2f, true) * 0.02, true);
        
        if (approx.size() == 4 || (approx.size() >= 5 && approx.size() <= 8)) {
            std::vector<cv::Point> approxPoints(approx.begin(), approx.end());
            
            bool isValidShape = isShape(approxPoints, approx.size(), cosineThreshold, minArea);
            
            if (isValidShape) {
                cv::Rect boundingBox = cv::boundingRect(approxPoints);
                
                // Ensure bounding box meets minimum width and height
                if (boundingBox.width >= minWidth && boundingBox.height >= minHeight) {
                    // Draw only valid bounding boxes
                    cv::Scalar color = (approx.size() == 4) ? cv::Scalar(0, 0, 255) : cv::Scalar(255, 0, 0);
                    cv::polylines(result, approxPoints, true, color, 2);
                    
                    CGFloat normalizedWidth = boundingBox.width / imageSize.width;
                    CGFloat normalizedHeight = boundingBox.height / imageSize.height;
                    CGFloat xCenter = 1.0 - ((boundingBox.x + boundingBox.width / 2.0) / imageSize.width);
                    
                    // Flip the yCenter to match ARKit's coordinate system
                    CGFloat yCenter = 1.0 - (boundingBox.y + boundingBox.height / 2.0) / imageSize.height;
                    
                    NSDictionary *boxData = @{
                        @"x_center": @(yCenter),
                        @"y_center": @(xCenter),
                        @"width": @(normalizedWidth),
                        @"height": @(normalizedHeight)
                    };
                    
                    [normalizedBoundingBoxes addObject:boxData];
                }
            }
        }
    }
    
    UIImage *resultImage = MatToUIImage(result);
    
    // Print the total number of bounding boxes found
    std::cout << "Total bounding boxes added: " << [normalizedBoundingBoxes count] << std::endl;
    
    return @{
        @"image": resultImage,
        @"boundingBoxes": normalizedBoundingBoxes
    };
}

/*
+ (UIImage *)detectShapesAndRender:(UIImage *)image inScene:(ARSCNView *)sceneView withCamera:(ARCamera *)camera {
    NSLog(@"Starting shape detection and AR drawing...");
    
    cv::Mat mat;
    [image convertToMat:&mat alphaExists:true];
    
    NSLog(@"Image converted to cv::Mat.");
    
    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGR2GRAY);
    NSLog(@"Converted image to grayscale.");

    cv::Mat edges;
    cv::Canny(gray, edges, 50, 150);
    NSLog(@"Performed Canny edge detection.");

    cv::Mat blurredEdges;
    cv::blur(edges, blurredEdges, cv::Size(5, 5));
    NSLog(@"Blurred edges to make them more visible.");

    cv::Mat dilatedEdges;
    cv::dilate(blurredEdges, dilatedEdges, cv::Mat(), cv::Point(-1, -1), 3);
    NSLog(@"Dilated edges to thicken them.");

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(dilatedEdges, contours, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);
    NSLog(@"Found %zu contours in the image.", contours.size());

    cv::Mat result = cv::Mat::zeros(mat.size(), CV_8UC3);

    double cosineThreshold = 0.2;
    double minArea = 1000.0;

    for (const auto& contour : contours) {
        std::vector<cv::Point2f> contour2f;
        cv::Mat(contour).convertTo(contour2f, CV_32F);
        std::vector<cv::Point2f> approx;
        cv::approxPolyDP(contour2f, approx, cv::arcLength(contour2f, true) * 0.02, true);

        NSLog(@"Detected shape with %zu sides.", approx.size());

        if (approx.size() >= 4 && approx.size() <= 8) {
            std::vector<cv::Point> approxPoints(approx.begin(), approx.end());
            if (isShape(approxPoints, approx.size(), cosineThreshold, minArea)) {
                NSLog(@"Shape passed the criteria check.");

                // Calculate the bounding box
                cv::Rect boundingBox = cv::boundingRect(approxPoints);
                NSLog(@"Bounding box calculated: x=%d, y=%d, width=%d, height=%d", boundingBox.x, boundingBox.y, boundingBox.width, boundingBox.height);

                // Convert the bounding box points from image space to normalized screen space
                CGPoint topLeft = CGPointMake(boundingBox.x, boundingBox.y);
                CGPoint bottomRight = CGPointMake(boundingBox.x + boundingBox.width, boundingBox.y + boundingBox.height);

                CGPoint normTopLeft = CGPointMake(topLeft.x / mat.cols, topLeft.y / mat.rows);
                CGPoint normBottomRight = CGPointMake(bottomRight.x / mat.cols, bottomRight.y / mat.rows);

                NSLog(@"Normalized top left: (%f, %f), bottom right: (%f, %f)", normTopLeft.x, normTopLeft.y, normBottomRight.x, normBottomRight.y);

                // Convert the normalized screen points to 3D points in the ARKit world space
                simd_float3 worldTopLeft = [self convert2DPointTo3D:normTopLeft withCamera:camera];
                simd_float3 worldBottomRight = [self convert2DPointTo3D:normBottomRight withCamera:camera];

                NSLog(@"World coordinates - Top left: (%f, %f, %f), Bottom right: (%f, %f, %f)", worldTopLeft.x, worldTopLeft.y, worldTopLeft.z, worldBottomRight.x, worldBottomRight.y, worldBottomRight.z);

                // Ensure the bounding box has a minimal size
                if (fabs(worldBottomRight.x - worldTopLeft.x) > 0.01 && fabs(worldBottomRight.y - worldTopLeft.y) > 0.01) {
                    // Create the bounding box in AR
                    SCNBox *box = [SCNBox boxWithWidth:fabs(worldBottomRight.x - worldTopLeft.x)
                                                 height:fabs(worldBottomRight.y - worldTopLeft.y)
                                                 length:0.01
                                          chamferRadius:0];

                    box.firstMaterial.diffuse.contents = [UIColor redColor];

                    SCNNode *boxNode = [SCNNode nodeWithGeometry:box];
                    boxNode.position = SCNVector3Make(worldTopLeft.x, worldTopLeft.y, worldTopLeft.z);

                    NSLog(@"Adding box node to AR scene at position (%f, %f, %f).", boxNode.position.x, boxNode.position.y, boxNode.position.z);

                    [sceneView.scene.rootNode addChildNode:boxNode];
                } else {
                    NSLog(@"Bounding box is too small to be rendered.");
                }
            } else {
                NSLog(@"Shape did not pass the criteria check.");
            }
        } else {
            NSLog(@"Shape has an invalid number of sides.");
        }
    }

    UIImage *resultImage = MatToUIImage(result);
    NSLog(@"Returning the result image after processing.");
    return resultImage;
}

// Helper method to convert 2D point to 3D point in ARKit
+ (simd_float3)convert2DPointTo3D:(CGPoint)point withCamera:(ARCamera *)camera {
    NSLog(@"Converting 2D point (%f, %f) to 3D point.", point.x, point.y);

    // Convert the 2D point to a 3D ray from the camera's projection matrix
    simd_float4 screenPoint = simd_make_float4(point.x, point.y, -1.0, 1.0);
    simd_float4 worldPoint = simd_mul(camera.projectionMatrix, screenPoint);
    simd_float3 result = simd_make_float3(worldPoint) / worldPoint.w;

    NSLog(@"Converted 2D point to 3D coordinates: (%f, %f, %f)", result.x, result.y, result.z);
    return result;
}
*/


@end
