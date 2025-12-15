// app/javascript/controllers/index.js

import { application } from "./application";

// Import controllers via importmap alias (IMPORTANT)
import HelloController from "controllers/hello_controller";
import ExampleController from "controllers/example_controller";

// Register controllers
application.register("hello", HelloController);
application.register("example", ExampleController);

console.log("✅ Stimulus controllers registered");
