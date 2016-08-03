//
//  LXDismissAnimation.m
//  EvePopViewController
//
//  Created by Harry Duan on 8/2/16.
//  Copyright © 2016 Harry_Duan. All rights reserved.
//

#import "LXDismissAnimation.h"
#import <UIKit/UIKit.h>

@implementation LXDismissAnimation

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext {
    return 0.4f;
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    UIView *containerView = [transitionContext containerView];
    containerView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    fromVC.view.center = CGPointMake(screenWidth / 2.f, screenHeight / 2.f);
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    [UIView animateWithDuration:duration animations:^{
        fromVC.view.transform = CGAffineTransformMakeTranslation(0, 500);
        containerView.backgroundColor = [UIColor clearColor];
    } completion:^(BOOL finished) {
        [transitionContext completeTransition:YES];
    }];
}

@end
