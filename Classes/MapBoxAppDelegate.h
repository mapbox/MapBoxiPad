//
//  MapBoxAppDelegate.h
//  MapBoxiPadDemo
//
//  Created by Justin R. Miller on 6/17/10.
//  Copyright Code Sorcery Workshop 2010. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MapBoxMainViewController;

@interface MapBoxAppDelegate : NSObject <UIApplicationDelegate>
{
    UIWindow *window;
    MapBoxMainViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet MapBoxMainViewController *viewController;

@end