#import <Cocoa/Cocoa.h>

static void drawIcon(CGContextRef ctx, CGFloat size) {
  // Background gradient: Windows 11 Fluent Blue
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGFloat locations[] = {0.0, 1.0};
  CGFloat colors[] = {
      0.00, 0.47, 0.84, 1.00, // Win11 Accent Blue
      0.00, 0.30, 0.65, 1.00  // Deeper Navy Blue
  };
  CGGradientRef grad =
      CGGradientCreateWithColorComponents(cs, colors, locations, 2);

  // Rounded Squircle
  CGFloat corner = size * 0.22;
  CGRect rect = CGRectMake(size * 0.05, size * 0.05, size * 0.90, size * 0.90);
  CGPathRef path = CGPathCreateWithRoundedRect(rect, corner, corner, NULL);

  CGContextSaveGState(ctx);
  CGContextAddPath(ctx, path);
  CGContextClip(ctx);
  CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, size),
                              CGPointMake(0, 0), 0);
  CGContextRestoreGState(ctx);

  CGGradientRelease(grad);
  CGPathRelease(path);

  // Draw 3 audio mixer vertical faders
  CGFloat faderSpacing = size * 0.22;
  CGFloat startX = size * 0.28;
  CGFloat faderTop = size * 0.75;
  CGFloat faderBottom = size * 0.25;

  CGFloat thumbHeights[] = {0.65, 0.40, 0.52};

  for (int i = 0; i < 3; i++) {
    CGFloat x = startX + i * faderSpacing;

    // Track
    CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.35);
    CGContextSetLineWidth(ctx, size * 0.04);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, x, faderBottom);
    CGContextAddLineToPoint(ctx, x, faderTop);
    CGContextStrokePath(ctx);

    // Lower active track
    CGFloat thumbY = faderBottom + (faderTop - faderBottom) * thumbHeights[i];
    CGContextSetRGBStrokeColor(ctx, 0.40, 0.85, 1.0, 0.95);
    CGContextMoveToPoint(ctx, x, faderBottom);
    CGContextAddLineToPoint(ctx, x, thumbY);
    CGContextStrokePath(ctx);

    // Thumb knob
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGRect knobRect = CGRectMake(x - size * 0.065, thumbY - size * 0.035,
                                 size * 0.13, size * 0.07);
    CGPathRef knobPath =
        CGPathCreateWithRoundedRect(knobRect, size * 0.02, size * 0.02, NULL);
    CGContextAddPath(ctx, knobPath);
    CGContextFillPath(ctx);
    CGPathRelease(knobPath);
  }

  CGColorSpaceRelease(cs);
}

static void saveImage(NSString *path, CGFloat size) {
  size_t s = (size_t)size;
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(NULL, s, s, 8, s * 4, cs,
                                           kCGImageAlphaPremultipliedLast |
                                               kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(cs);

  drawIcon(ctx, size);

  CGImageRef img = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);

  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
  CGImageRelease(img);
  NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                  properties:@{}];
  [png writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2)
      return 1;
    NSString *dest = [NSString stringWithUTF8String:argv[1]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dest
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    int sizes[] = {16, 32, 64, 128, 256, 512, 1024};
    for (int i = 0; i < 7; i++) {
      int s = sizes[i];
      saveImage([dest stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"icon_%dx%d.png", s, s]],
                s);
      if (s <= 512) {
        saveImage(
            [dest stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"icon_%dx%d@2x.png", s, s]],
            s * 2);
      }
    }
  }
  return 0;
}
