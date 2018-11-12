# H264 frame header

## Decode
### NALU
Ref: [stackoverflow](https://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer)
`[header(4bytes)]` `[type(2bytes)]` `[mb-slide(1bit)]`
*trans header from BigEndian to Little (TCP:Big / AppleCPU:Little)*
#### header - 1/2/4 bytes ,AVCC format
```
(00 00 00 01) [hex]
```
#### type - 2 bytes
```
(0000 0000)
bit 0 -> forbidden zero
bit 1~3 -> ref
bit 4~5 -> unit type (total 24 type)
```
#### mb-slice - 1 bit
```
0 -> first
1 -> multi
```
**Result -> CMSampleBufferCreate -> AVSamplebufferLayer**

# Encode
Ref:http://stackoverflow.com/questions/18244513/strange-h-264-nal-headers
setup vtcompression
```objc
CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &parmCount, &nalUnitLength );
CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsSize, &parmCount, &nalUnitLength );
CMBlockBufferRef my_buffer = CMSampleBufferGetDataBuffer(sampleBuffer);
NSMutableData * data = [[NSMutableData alloc] initWithBytes:sampledata length:buffer_length];
// Replace "header length" to "NALU 0x00000001" in each CMBlockBuffer(which actually contains mpeg4 data), to become a raw H.264 stream data
//DUE TO iOS Using not Annex B
[data replaceBytesInRange:NSMakeRange(offset, 4) withBytes:nal length:4];
```
​
