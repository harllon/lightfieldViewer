// This part of a flash light field viewer written by Andrew Adams
// http://www.stanford.edu/~abadams
// This code is public domain. 

package lightfield {
    import flash.events.Event;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.display.Loader;
    import flash.display.Bitmap;
    import flash.events.IOErrorEvent;
    import flash.display.BitmapData;
    import flash.geom.*;
    import mx.controls.Alert;
    import flash.utils.ByteArray;

    public class SubApertureImage {
	public var u:Number, v:Number;
	public var image:BitmapData;
	public var loader:Loader;
	public var url:String;
	public var completeHandler:Function;
	public var index:uint;

	public function SubApertureImage(data:ByteArray, url_:String, u_:Number, v_:Number, completeHandler_:Function, index_:uint) {
	    image = null;
	    u = u_;
	    v = v_;
	    url = url_;
	    completeHandler = completeHandler_;
	    index = index_;
	    loader = new Loader();	    
	    try {
		loader.loadBytes(data);
	    } catch(error:SecurityError) {
		Alert.show("Security error loading light field. Was the program compiled with the appropriate --use-network setting?");
	    }
	    loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
	    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, loadComplete);
	}

	private function errorHandler(event:IOErrorEvent):void {
	    Alert.show("Error loading light field: " + event.text);
        }

	private function loadComplete(event:Event):void {
	    try {		
		image = (loader.content as Bitmap).bitmapData;
	    } catch (e:Object) {
		Alert.show("Bad sub-aperture image: " + url);
	    }

	    if (image == null) Alert.show("Bad sub-aperture image: " + url);

	    completeHandler(index);
	}
	
    }
}