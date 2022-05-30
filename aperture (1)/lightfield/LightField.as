// This part of a flash light field viewer written by Andrew Adams
// http://www.stanford.edu/~abadams
// This code is public domain. 

package lightfield {
    import flash.events.*;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.xml.*;
    import flash.display.BitmapData;
    import flash.geom.*;
    import mx.utils.URLUtil;
    import flash.utils.Timer;
    import flash.events.TimerEvent;
    import mx.core.*;
    import mx.controls.*;
    import deng.fzip.*;
    import flash.utils.ByteArray;

    public class LightField {

	public var fmin:Number, fmax:Number;
	public var views:uint, viewsLoaded:uint, background:uint;
	public var width:uint, height:uint;
	public var uScale:Number, vScale:Number;
	public var url:String;

	private var loadProgressHandler:Function;
	private var zip:FZip;
	private var xml:XML;
	private var avgU:Number, avgV:Number, scale:Number;

	private var tmp:BitmapData, target:BitmapData, totalAlpha:Number;
	private var angularSamples:UIComponent;
	private var renderingInProgress:Boolean;
	private var split:uint;
	private var imagesToBlend:Array;
	private var renderTimer:Timer;

	private var depthImage:DepthImage;
	private var subApertureImages:Array;

	private const DECOMPRESSION_THREADS:uint = 20;

	public function LightField(url_:String, loadProgressHandler_:Function):void {
	    subApertureImages = new Array();
	    imagesToBlend = new Array();
	    depthImage = null;
	    renderingInProgress = false;
	    url = url_;
	    loadProgressHandler = loadProgressHandler_;
	    renderTimer = new Timer(1);
            renderTimer.addEventListener(TimerEvent.TIMER, continueRendering);
	    width = height = views = viewsLoaded = 0;

	    zip = new FZip();

	    zip.addEventListener(Event.COMPLETE, loadComplete);
	    zip.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
	    zip.addEventListener(ProgressEvent.PROGRESS, progressHandler);

	    try {
		zip.load(new URLRequest(url));
	    } catch(error:SecurityError) {
		Alert.show("Security error loading light field. Was the program compiled with the appropriate --use-network setting?");
	    }
	}

        public function isFullyLoaded():Boolean {
	    return (views > 0 && views == viewsLoaded);
	}

        public function hasDepthImage():Boolean {
	    return (depthImage != null);
	}

	public function autoFocus(x:int, y:int):Number {
	    if (depthImage == null) return -1;
	    var val:Number = (depthImage.image.getPixel(x, y) & 255) - 128;
	    val -= fmin;
	    val /= (fmax - fmin);
	    return val;
	}
	    
	private function errorHandler(event:IOErrorEvent):void {
	    Alert.show("Error loading light field: " + event.text);
        }

	private function loadComplete(event:Event):void {
	    // find the xml file in the archive
	    var file:FZipFile;
	    var i:uint;
	    for (i = 0; i < zip.getFileCount(); i++) {
		file = zip.getFileAt(i);
		if (file.filename.substr(file.filename.length-4, 4) == ".xml") break;
	    }
	    
	    if (i == zip.getFileCount()) {
		Alert.show("No xml file found in archive!");
		return;
	    }

	    try {
		xml = new XML(file.content);
	    } catch (e:TypeError) {
		Alert.show("Could not parse the XML file.");
	    }	    

	    if (xml.hasOwnProperty("@fmin")) fmin = Number(xml.@fmin);
	    else fmin = -50;
	    if (xml.hasOwnProperty("@fmax")) fmax = Number(xml.@fmax);
	    else fmax = 50;
	    if (xml.hasOwnProperty("@background")) background = 0xff000000 | uint(xml.@background);
	    else background = 0xffcccccc;
	    if (xml.hasOwnProperty("@uscale")) uScale = Number(xml.@uscale);
	    else uScale = 1.0;
	    if (xml.hasOwnProperty("@vscale")) vScale = Number(xml.@vscale);
	    else vScale = 1.0;

	    var truncatedURL:String = url.substring(0, url.lastIndexOf("/")+1);

	    if (xml.hasOwnProperty("@depth")) {		
		depthImage = new DepthImage(zip.getFileByName(xml.@depth).content, xml.@depth, loadDepthImageComplete);
		views = 1;
	    }	  

	    views += xml.subaperture.length(); 

	    var u:Number, v:Number, maxU:Number, maxV:Number, minU:Number, minV:Number;
	    avgV = avgU = 0;
	    // calculate angular extent of this light field
	    for (i = 0; i < xml.subaperture.length(); i++) {
		u = Number(xml.subaperture[i].@u);
		v = Number(xml.subaperture[i].@v);
		avgU += u;
		avgV += v;
		if (i == 0 || u < minU) minU = u;
		if (i == 0 || u > maxU) maxU = u;
		if (i == 0 || v < minV) minV = v;
		if (i == 0 || v > maxV) maxV = v;
	    }
	    avgU /= xml.subaperture.length();
	    avgV /= xml.subaperture.length();
	    var uS:Number = 0.9/(maxU - minU);
	    var vS:Number = 0.9/(maxV - minV);
	    scale = (uS < vS ? uS : vS);

	    // load the first DECOMPRESSION_THREADS sub aperture images
	    for (i=0;i<DECOMPRESSION_THREADS;i++) {
		var filename:String = xml.subaperture[i].@src;
		var zipFile:FZipFile = zip.getFileByName(filename);
		if (zipFile == null) {
		    Alert.show("Could not find file: " + filename + " in light field");
		    return;
		}
		var data:ByteArray = zipFile.content;
		subApertureImages.push(new SubApertureImage(data,
							    filename,
							    scale*(Number(xml.subaperture[i].@u)-avgU),
							    scale*(Number(xml.subaperture[i].@v)-avgV), 
							    loadSubApertureImageComplete, i));	    
	    }	   
	}

        public function loadDepthImageComplete():void {
	    viewsLoaded += 1;
	    width  = depthImage.image.width;
	    height = depthImage.image.height;
	    loadProgressHandler(viewsLoaded, views);
	}

        public function loadSubApertureImageComplete(i:int):void {
	    viewsLoaded += 1;
	    if (width == 0 && subApertureImages[0].image != null) {
		width  = subApertureImages[0].image.width;
		height = subApertureImages[0].image.height;
	    }
	    loadProgressHandler(viewsLoaded, views);

	    var next:uint = i + DECOMPRESSION_THREADS;
	    if (next < xml.subaperture.length()) {

		var filename:String = xml.subaperture[next].@src;
		var zipFile:FZipFile = zip.getFileByName(filename);
		if (zipFile == null) {
		    Alert.show("Could not find file: " + filename + " in light field");
		    return;
		}
		var data:ByteArray = zipFile.content;
		var u:Number = Number(xml.subaperture[next].@u);
		var v:Number = Number(xml.subaperture[next].@v);


		var s:SubApertureImage = new SubApertureImage(data,
							      filename,
							      scale*(u-avgU),
							      scale*(v-avgV), 
							      loadSubApertureImageComplete, next);

		subApertureImages.push(s);

	    }
	}

        public function progressHandler(progressEvent:ProgressEvent):void {
	    loadProgressHandler(progressEvent.bytesLoaded, progressEvent.bytesTotal);
	}

        public function render(u:Number, v:Number, r:Number, focus:Number, target_:BitmapData, angularSamples_:UIComponent):void {
	    if (renderingInProgress || imagesToBlend.length > 0) {
		// interrupt any render-in-progress
		imagesToBlend = new Array();
		renderTimer.stop();
	    }
	    if (viewsLoaded < views) return;

	    target = target_;
	    angularSamples = angularSamples_;

	    renderingInProgress = true;

	    focus *= (fmax - fmin);
	    focus += fmin;

	    var dst:Point = new Point(0, 0);
	    
	    // to render the light field, we'll incrementally blend
 	    // in new subaperture images, these variables keep track
	    // of the blending
	    var alpha:Number;

	    var srcRect:Rectangle = new Rectangle(0, 0, subApertureImages[0].image.width, subApertureImages[0].image.height);

	    // blank the output
	    target.lock();
	    target.fillRect(srcRect, background);
	    angularSamples.graphics.clear();
	    angularSamples.graphics.lineStyle(2, 0, 0.2);
	    
	    // iterate over every subaperture image, making a list of which subaperture images we need to blend
	    var closest:SubApertureImage, closestDelta:Number = 100000;
	    for each (var subAperture:SubApertureImage in subApertureImages) {
		var subApPoint:Point = new Point((subAperture.u+0.5)*angularSamples.width,
						 (subAperture.v+0.5)*angularSamples.height);
		angularSamples.graphics.drawCircle(subApPoint.x, subApPoint.y, 1);

		// evaluate the circle filter
		var delta:Number = (subAperture.u-u)*(subAperture.u-u) + (subAperture.v-v)*(subAperture.v-v) - r*r;
		if (delta < 0) {
		    alpha = 1;		    
		} else {
		    alpha = 0;
		}
		if (delta < closestDelta) {
		    closestDelta = delta;
		    closest = subAperture;
		}
		if (alpha > 0) {
		    imagesToBlend.push({image:subAperture.image, 
					x:subAperture.u*focus*2*uScale,
					y:subAperture.v*focus*2*vScale,
					alpha:alpha,
					distance:delta,
                                        u:subAperture.u, v:subAperture.v});
		    
		}
	    }

	    var obj:Object;

	    // sort the array by distance from the center of the aperture, so that gets rendered first when dragging
	    imagesToBlend.sortOn("distance");

	    // check to see if we missed all samples
	    if (imagesToBlend.length == 0) {
		// calculate the destination location as a function of aperture position and focus
		dst.x = closest.u*focus*2;
		dst.y = closest.v*focus*2;
		    
		// blend
		angularSamples.graphics.lineStyle(2, 0x0000ff, 0.8);
		angularSamples.graphics.drawCircle((closest.u+0.5)*angularSamples.width, (closest.v+0.5)*angularSamples.height, 1);
		target.copyPixels(closest.image, srcRect, dst);
		renderingInProgress = false;
	    } else if (imagesToBlend.length > 15) {  // two level blending to avoid quantization, with deferred rendering for responsiveness
		// pick a level to split at
		split = uint(Math.sqrt(imagesToBlend.length)+0.5);
		if (split < 8) split = 8;

		// make an intermediate blending target
		if (tmp == null || tmp.width != srcRect.width || tmp.height != srcRect.height)
		    tmp = new BitmapData(srcRect.width, srcRect.height);

		// defer the actual blending
		totalAlpha = 0;

		// start the render timer to call the deferred blend method later
		renderTimer.start();

		// do one render so we see something
		continueRendering(null);

	    } else { // single level blending
		totalAlpha = 0;
		while (imagesToBlend.length > 0) {
		    obj = imagesToBlend.pop();
		    totalAlpha += obj.alpha;
		    angularSamples.graphics.lineStyle(2, 0x0000ff, 0.8);
		    angularSamples.graphics.drawCircle((obj.u+0.5)*angularSamples.width, (obj.v+0.5)*angularSamples.height, 1);
		    target.merge(obj.image, srcRect, new Point(obj.x, obj.y),
				 obj.alpha/totalAlpha*255, obj.alpha/totalAlpha*255,
				 obj.alpha/totalAlpha*255, obj.alpha/totalAlpha*255);		
		}
		renderingInProgress = false;
	    }

	    target.unlock();


	}
	    
	
        public function continueRendering(event:Event):void {
	    if (renderingInProgress) {
		target.lock();
		var obj:Object;
		var srcRect:Rectangle = new Rectangle(0, 0, subApertureImages[0].image.width, subApertureImages[0].image.height);
		var tmpAlpha:Number = 0;
		tmp.fillRect(srcRect, background);
		for (var j:uint = 0; j < split && imagesToBlend.length > 0; j++) {
		    obj = imagesToBlend.pop();
		    tmpAlpha += obj.alpha;
		    angularSamples.graphics.lineStyle(2, 0x0000ff, 0.8);
		    angularSamples.graphics.drawCircle((obj.u+0.5)*angularSamples.width, (obj.v+0.5)*angularSamples.height, 1);
		    tmp.merge(obj.image, srcRect, new Point(obj.x, obj.y),
			      obj.alpha/tmpAlpha*255, obj.alpha/tmpAlpha*255,
			      obj.alpha/tmpAlpha*255, obj.alpha/tmpAlpha*255);		
		}
		    
		totalAlpha += tmpAlpha;
		target.merge(tmp, srcRect, new Point(0, 0),
			     tmpAlpha/totalAlpha*255, tmpAlpha/totalAlpha*255,
			     tmpAlpha/totalAlpha*255, tmpAlpha/totalAlpha*255);				    
		target.unlock();
	    }	    

	    if (imagesToBlend.length == 0) {
		renderingInProgress = false;
		renderTimer.stop();
	    }

	}
    }
}