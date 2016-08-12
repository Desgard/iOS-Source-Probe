//
//  ViewController.m
//  TestCopy
//
//  Created by 段昊宇 on 16/8/12.
//  Copyright © 2016年 Desgard_Duan. All rights reserved.
//

#import "ViewController.h"
#import "Person.h"

@interface ViewController ()

@property (strong, nonatomic) Person* one;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self test6];
    
}

- (void)test1 {
    self.one = [[Person alloc] init];
    NSMutableString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.s_name = name;
    
    NSLog(@"%@", self.one.s_name);
    
    [name appendString:@" Source Probe"];
    
    NSLog(@"%@", self.one.s_name);
}

- (void)test2 {
    self.one = [[Person alloc] init];
    NSString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.s_name = name;
    
    NSLog(@"%@", self.one.s_name);
    
    name = @"iOS Source Probe";
    
    NSLog(@"%@", self.one.s_name);
}

- (void)test3 {
    self.one = [[Person alloc] init];
    NSMutableString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.c_name = name;
    
    NSLog(@"%@", self.one.c_name);
    
    [name appendString:@" Source Probe"];
    
    NSLog(@"%@", self.one.c_name);
}

- (void)test4 {
    NSMutableString *str = [NSMutableString stringWithFormat:@"iOS"];
    
    NSLog(@"%p", str);
    
    NSString *str_a = str;
    
    NSLog(@"%p", str_a);
    
    NSString *str_b = [str copy];
    
    NSLog(@"%p", str_b);
}

- (void)test5 {
    self.one = [[Person alloc] init];
    NSString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.c_name = name;
    
    NSLog(@"%@", self.one.c_name);
    
    name = @"iOS Source Probe";
    
    NSLog(@"%@", self.one.c_name);
    
    NSString *str = [NSString stringWithFormat:@"iOS"];
    
    NSLog(@"%p", str);
    
    NSString *str_a = str;
    
    NSLog(@"%p", str_a);
    
    NSString *str_b = [str mutableCopy];
    
    NSLog(@"%p", str_b);
}

- (void)test6 {
    NSMutableString *str = [NSMutableString stringWithFormat:@"iOS"];
    NSLog(@"%p", str);
    NSMutableString *str2 = [str copy];
    NSLog(@"%p", str2);
}

- (void)test7 {
    NSMutableString *str = [NSMutableString stringWithFormat:@"iOS"];
    NSLog(@"%p", str);
    NSMutableString *str2 = [str mutableCopy];
    NSLog(@"%p", str2);
}

@end
