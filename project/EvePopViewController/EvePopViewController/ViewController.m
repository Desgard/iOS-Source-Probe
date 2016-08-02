//
//  ViewController.m
//  EvePopViewController
///  Created by Harry Duan on 8/1/16.
//  Copyright © 2016 Harry_Duan. All rights reserved.
//

#import "ViewController.h"
#import "LXNotePopUpViewController.h"

@interface ViewController ()<ModalViewControllerDelegate ,UIViewControllerTransitioningDelegate>


@property (strong, nonatomic) LXNotePopUpViewController* toVC;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor grayColor];
    self.toVC = [LXNotePopUpViewController new];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(80, 210, 160, 40);
    [btn setTitle:@"click me" forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor redColor];
    [btn addTarget:self
            action:@selector(buttonClick:)
  forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}

- (void) buttonClick: (id)sender {
    LXNotePopUpViewController *vc = [LXNotePopUpViewController notePopUpViewController];
    vc.delegate = self;
    
//    vc.noteText = @"Glow, GLOW, glow! ";
    [vc setSaveHandler:^(NSString *words, NSUInteger cnt, LXNotePopUpViewController *vc) {
        NSLog(@"%@", words);
        NSLog(@"%lu", cnt);
    }];
    
    [self presentViewController:vc animated:YES completion:nil];
}



- (void)modalViewControllerDidClickDismissButton: (LXNotePopUpViewController *)viewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end
