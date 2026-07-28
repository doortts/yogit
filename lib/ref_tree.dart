class RefTreeNode {
  const RefTreeNode({
    required this.segment,
    this.fullName,
    this.children = const [],
  });

  final String segment;
  final String? fullName;
  final List<RefTreeNode> children;
}

class _MutableRefTreeNode {
  _MutableRefTreeNode(this.segment);

  final String segment;
  String? fullName;
  final Map<String, _MutableRefTreeNode> children = {};

  RefTreeNode freeze() => RefTreeNode(
    segment: segment,
    fullName: fullName,
    children: [for (final child in children.values) child.freeze()],
  );
}

List<RefTreeNode> buildRefTree(Iterable<String> names) {
  final roots = <String, _MutableRefTreeNode>{};
  for (final name in names) {
    final segments = name.split('/');
    var level = roots;
    _MutableRefTreeNode? node;
    for (final segment in segments) {
      node = level.putIfAbsent(segment, () => _MutableRefTreeNode(segment));
      level = node.children;
    }
    node!.fullName = name;
  }
  return [for (final root in roots.values) root.freeze()];
}

List<String> sortTagsNewestFirst(
  Iterable<String> names,
  Map<String, int> creatorTimes,
) {
  final sorted = names.toList();
  sorted.sort((left, right) {
    final leftTime = creatorTimes[left];
    final rightTime = creatorTimes[right];
    if (leftTime != null && rightTime != null) {
      final byTime = rightTime.compareTo(leftTime);
      if (byTime != 0) return byTime;
      return left.compareTo(right);
    }
    if (leftTime != null) return -1;
    if (rightTime != null) return 1;
    return left.compareTo(right);
  });
  return sorted;
}
