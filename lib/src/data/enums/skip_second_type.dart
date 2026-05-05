///跳过多少秒
///skip how many seconds
enum SkipSecondType {
  second10(value: 10),
  second15(value: 15),
  second30(value: 30),
  second45(value: 45),
  second60(value: 60);

  final int value;
  const SkipSecondType({required this.value});

  Duration get duration => Duration(seconds: value);
}
