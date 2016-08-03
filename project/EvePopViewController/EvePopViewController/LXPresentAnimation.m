//
//  LXPresentAnimation.m
//  EvePopViewController
//
//  Created by Harry Duan on 8/1/16.
//  Copyright © 2016 Harry_Duan. All rights reserved.
//

#import "LXPresentAnimation.h"
#import "LXNotePopUpViewController.h"

@interface LXPresentAnimation ()

@property (weak, nonatomic) UIViewController *presentedViewController;

@end

@implementation LXPresentAnimation


- (NSTimeInterval) transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.3;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    LXNotePopUpViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    toViewController.view.center = CGPointMake(screenWidth / 2.f, screenHeight / 2.f);
    CGAffineTransform t = CGAffineTransformMakeTranslation(0, -500);
    t = CGAffineTransformRotate(t, -M_PI / 18.0);
    toViewController.view.transform = t;
    [transitionContext containerView].backgroundColor = [UIColor clearColor];
    [[transitionContext containerView] addSubview:toViewController.view];
    
    [UIView animateWithDuration:0.45
                          delay:0
         usingSpringWithDamping:0.6
          initialSpringVelocity:0
                        options:0
                     animations:^{
                         toViewController.view.transform = CGAffineTransformIdentity;
                         toViewController.view.alpha = 1;
                         toViewController.view.center = CGPointMake(screenWidth / 2.f, screenHeight / 2.f);
                         [transitionContext containerView].backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
                     }
                     completion:^(BOOL finished) {
                         [transitionContext completeTransition:YES];
                     }];
    
    
}

@end
