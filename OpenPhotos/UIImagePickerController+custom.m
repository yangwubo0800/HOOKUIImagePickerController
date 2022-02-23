//
//  NSObject+custom.m
//  OpenPhotos
//
//  Created by Allen Gao on 2019/1/21.
//  Copyright © 2019 Allen Gao. All rights reserved.
//

#import "UIImagePickerController+custom.h"
#import <objc/runtime.h>
#import <MobileCoreServices/MobileCoreServices.h>


@implementation UIImagePickerController (custom)

static BOOL isDelegateMethodHooked = false;

+ (void)hookDelegate {
    SEL swizzledSEL = @selector(swizzled_imagePickerController:didFinishPickingMediaWithInfo:);
    SEL originSEL = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
    
    if (swizzledSEL && originSEL) {
        Class class = NSClassFromString(@"WKFileUploadPanel");
        hook_delegateMethod(class, originSEL, [UIImagePickerController class], swizzledSEL, swizzledSEL);
    }
}

+ (void)unHookDelegate {
    SEL swizzledSEL = @selector(swizzled_imagePickerController:didFinishPickingMediaWithInfo:);
    SEL originSEL = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
    Class class = NSClassFromString(@"WKFileUploadPanel");
    unHook_delegateMethod(class,swizzledSEL,originSEL);
}

/**
 替换代理方法的实现
 */
static void hook_delegateMethod(Class originalClass, SEL originalSel, Class replacedClass, SEL replacedSel, SEL noneSel)  {
    //原实例方法
    Method originalMethod = class_getInstanceMethod(originalClass, originalSel);
    //替换的实例方法
    Method replacedMethod = class_getInstanceMethod(replacedClass, replacedSel);
    
    if (!originalMethod) {// 如果没有实现 delegate 方法，则手动动态添加
        Method noneMethod = class_getInstanceMethod(replacedClass, noneSel);
        class_addMethod(originalClass, originalSel, method_getImplementation(noneMethod), method_getTypeEncoding(noneMethod));
        return;
    }
    
    // 向实现 delegate 的类中添加新的方法
    class_addMethod(originalClass, replacedSel, method_getImplementation(replacedMethod), method_getTypeEncoding(replacedMethod));
    
    // 重新拿到添加被添加的 method, 因为替换的方法已经添加到原类中了, 应该交换原类中的两个方法
    Method newMethod = class_getInstanceMethod(originalClass, replacedSel);
    if(!isDelegateMethodHooked && originalMethod && newMethod) {
        method_exchangeImplementations(originalMethod, newMethod);// 实现交换
        isDelegateMethodHooked = YES;
    }
}

/**
 恢复代理方法的实现
 */
static void unHook_delegateMethod(Class originalClass, SEL originalSel, SEL replacedSel){
    if(isDelegateMethodHooked) {
        Method originalMethod = class_getInstanceMethod(originalClass, originalSel);
        Method replacedMethod = class_getInstanceMethod(originalClass, replacedSel);
        if (originalMethod && replacedMethod){
            // 重新拿到添加被添加的 method,这里是关键(注意这里 originalClass, 不 replacedClass), 因为替换的方法已经添加到原类中了, 应该交换原类中的两个方法
            Method newMethod = class_getInstanceMethod(originalClass, replacedSel);
            method_exchangeImplementations(originalMethod, newMethod);// 实现交换
            isDelegateMethodHooked = NO;
        }
    }
}

/**
 替换的代理实现

 @param picker picker
 @param info info
 */
- (void)swizzled_imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info{
    
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:info];
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        NSString *imageURLKey = @"UIImagePickerControllerImageURL";
        NSString *imageKey = @"UIImagePickerControllerOriginalImage";
        
        
        //UIImagePickerControllerReferenceURL设为空是关键一步。
        //相机是不会有asset URL,即referenceURL会为空，所以这里不需要传asset URL，直接传图片对象即可。
        //让WKFileUploadPanel以为从相册来的图片也是从相机来的
        [dict setValue:nil forKey:@"UIImagePickerControllerReferenceURL"];
        UIImage *originImage = [dict valueForKey:imageKey];;
    
        UIImage *targetImage = [UIImagePickerController compressImage:originImage];
        
        NSString *imageFilePath = [UIImagePickerController imageFilePath];
        [UIImagePickerController saveToSandBox:targetImage filePath:imageFilePath];
        NSURL *targetImageURL = [NSURL fileURLWithPath:imageFilePath];
        [dict setObject:targetImage forKey:imageKey];
        [dict setObject:targetImageURL forKey:imageURLKey];
    }else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        NSLog(@"视频文件, 将其保存到沙盒之中....");
        NSURL *url = [info objectForKey:UIImagePickerControllerMediaURL];
        NSString *videoPath = url.path;
        NSLog(@"视频原始路径videoPath=%@", videoPath);
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *videoFilePath = [UIImagePickerController videoFilePath];
        BOOL copyRes= [fileManager copyItemAtPath:videoPath toPath:videoFilePath error:nil];
        if (copyRes) {
            NSLog(@"拷贝文件成功到：%@",videoFilePath);
        }else{
            NSLog(@"拷贝文件失败");
        }
    }
  
    
    //方法的实现已经通过Method swizling交换了，所以这里调用的是原始实现
    [self swizzled_imagePickerController:picker didFinishPickingMediaWithInfo:dict];
}

+ (void)saveToSandBox:(UIImage *)image filePath:(NSString *)path {
//    NSData *data = UIImagePNGRepresentation(image);
    NSData *data = UIImageJPEGRepresentation(image, 0.5f);
    BOOL saveImage = [data writeToFile:path atomically:YES];
    if (saveImage) {
        NSLog(@"保存图片到沙盒成功 path=%@", path);
    }else{
        NSLog(@"保存图片到沙盒失败");
    }
}

+ (NSString *)imageFilePath {
    NSArray *documentDirectories =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                        NSUserDomainMask, YES);
    
    NSString *documentDirectory = [documentDirectories objectAtIndex:0];
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormater = [[NSDateFormatter alloc] init];
    dateFormater.dateFormat = @"yyyyMMddHHmmss";
    NSString *dateString = [dateFormater stringFromDate:date];
    NSString *fileName = [dateString stringByAppendingString:@".jpg"];
    return [documentDirectory stringByAppendingPathComponent:fileName];
}


+ (NSString *)videoFilePath {
    NSArray *documentDirectories =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                        NSUserDomainMask, YES);
    
    NSString *documentDirectory = [documentDirectories objectAtIndex:0];
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormater = [[NSDateFormatter alloc] init];
    dateFormater.dateFormat = @"yyyyMMddHHmmss";
    NSString *dateString = [dateFormater stringFromDate:date];
    NSString *fileName = [dateString stringByAppendingString:@".MOV"];
    return [documentDirectory stringByAppendingPathComponent:fileName];
}

/**
 压缩图片
 
 @param image 原始图片
 @return 加工完成的图片
 */
+ (UIImage *)compressImage:(UIImage *)image {
    return image;
}

@end
