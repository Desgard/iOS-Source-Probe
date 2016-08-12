//
//  Person.h
//  TestCopy
//
//  Created by 段昊宇 on 16/8/12.
//  Copyright © 2016年 Desgard_Duan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Person : NSObject

@property (strong, nonatomic) NSString* s_name;
@property (copy, nonatomic) NSString* c_name;

@end
