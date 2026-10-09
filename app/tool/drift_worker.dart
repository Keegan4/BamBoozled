// The web worker that runs the database in a browser. Compiled to web/drift_worker.js by
// tool/build_web.sh; not part of the app itself.
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
