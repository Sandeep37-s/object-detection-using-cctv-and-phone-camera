/// The 80 COCO classes the YOLO nano model detects, in class-ID order.
const List<String> kLabels = [
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
  'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
  'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag',
  'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
  'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
  'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon',
  'bowl', 'banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot',
  'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch', 'potted plant',
  'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote',
  'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
  'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
  'hair drier', 'toothbrush',
];

/// Class groups shown in the object filter screen: (name, first ID, last ID).
const List<(String, int, int)> kCategories = [
  ('People', 0, 0),
  ('Vehicles', 1, 8),
  ('Outdoor', 9, 13),
  ('Animals', 14, 23),
  ('Accessories', 24, 28),
  ('Sports', 29, 38),
  ('Kitchen', 39, 45),
  ('Food', 46, 55),
  ('Furniture', 56, 61),
  ('Electronics', 62, 67),
  ('Appliances', 68, 72),
  ('Indoor items', 73, 79),
];

/// Default selection for surveillance: people, vehicles and animals.
const Set<int> kDefaultClasses = {
  0, 1, 2, 3, 5, 7, 14, 15, 16, 17, 18, 19, //
};
