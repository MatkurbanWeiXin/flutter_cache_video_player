import 'dart:async';

/// 流分叉器，将一个数据流拆分为两个独立分支。
/// Stream splitter that forks a single data stream into two independent branches.
class StreamSplitter {
  final int highWaterMark;

  StreamSplitter({this.highWaterMark = 256 * 1024});

  /// 将源流拆分为两个相同内容的输出流。
  /// Splits the source stream into two output streams with identical content.
  (Stream<List<int>>, Stream<List<int>>) split(Stream<List<int>> source) {
    final controller1 = StreamController<List<int>>();
    final controller2 = StreamController<List<int>>();
    int buffered = 0;

    source.listen(
      (data) {
        controller1.add(data);
        controller2.add(data);
        buffered += data.length;
        if (buffered > highWaterMark) {
          buffered = 0;
        }
      },
      onDone: () {
        controller1.close();
        controller2.close();
      },
      onError: (error, stackTrace) {
        controller1.addError(error, stackTrace);
        controller2.addError(error, stackTrace);
      },
    );

    return (controller1.stream, controller2.stream);
  }
}
