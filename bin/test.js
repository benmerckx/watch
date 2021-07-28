(function ($global) { "use strict";
var haxe_iterators_ArrayIterator = function(array) {
	this.current = 0;
	this.array = array;
};
haxe_iterators_ArrayIterator.prototype = {
	hasNext: function() {
		return this.current < this.array.length;
	}
	,next: function() {
		return this.array[this.current++];
	}
};
function test_Run_main() {
	console.log("test/Run.hx:4:","123456789");
}
})({});
