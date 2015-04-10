/*******************************************************************************
 The MIT License (MIT)

 Copyright (c) 2014 Alexander Zolotarev <me@alex.bio> from Minsk, Belarus

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 *******************************************************************************/

#import "ViewController.h"

#import "C5T/ios_client.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  const CLLocationCoordinate2D coord = {12.12345678, -32.12345678};
  CLLocation * l = [[CLLocation alloc] initWithCoordinate:coord altitude:42.42424242 horizontalAccuracy:2.123456
      verticalAccuracy:12.123456 course:90.12345678 speed:1.2345678 timestamp:[NSDate date]];
  [AlohalyticsLite logEvent:@"ViewControllerDidLoad" withDictionary:[NSBundle mainBundle].infoDictionary atLocation:l];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  [AlohalyticsLite logEvent:@"didReceiveMemoryWarning"];
}

@end
