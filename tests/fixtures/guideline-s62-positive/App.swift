let files = FileManager.default.contentsOfDirectory(atPath: path)
List(files) { Text($0) }.navigationTitle("Documents")