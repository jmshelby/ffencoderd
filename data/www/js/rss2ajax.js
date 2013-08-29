//OBJECTS

//objects inside the RSS2Item object
function RSS2Enclosure(encElement)
{
	if (encElement == null)
	{
		this.url = null;
		this.length = null;
		this.type = null;
	}
	else
	{
		this.url = encElement.getAttribute("url");
		this.length = encElement.getAttribute("length");
		this.type = encElement.getAttribute("type");
	}
}

function RSS2Guid(guidElement)
{
	if (guidElement == null)
	{
		this.isPermaLink = null;
		this.value = null;
	}
	else
	{
		this.isPermaLink = guidElement.getAttribute("isPermaLink");
		this.value = guidElement.childNodes[0].nodeValue;
	}
}

function RSS2Source(souElement)
{
	if (souElement == null)
	{
		this.url = null;
		this.value = null;
	}
	else
	{
		this.url = souElement.getAttribute("url");
		this.value = souElement.childNodes[0].nodeValue;
	}
}

//object containing the RSS 2.0 item
function RSS2Item(itemxml)
{
	//required
	this.title;
	this.link;
	this.description;

	//optional vars
	this.author;
	this.comments;
	this.pubDate;

	//optional objects
	this.category;
	this.enclosure;
	this.guid;
	this.source;

	var properties = new Array("title", "link", "description", "author", "comments", "pubDate");
	var tmpElement = null;
	for (var i=0; i<properties.length; i++)
	{
		tmpElement = itemxml.getElementsByTagName(properties[i])[0];
		if (tmpElement != null)
			eval("this."+properties[i]+"=tmpElement.childNodes[0].nodeValue");
	}

	this.category = new RSS2Category(itemxml.getElementsByTagName("category")[0]);
	this.enclosure = new RSS2Enclosure(itemxml.getElementsByTagName("enclosure")[0]);
	this.guid = new RSS2Guid(itemxml.getElementsByTagName("guid")[0]);
	this.source = new RSS2Source(itemxml.getElementsByTagName("source")[0]);
}

//objects inside the RSS2Channel object
function RSS2Category(catElement)
{
	if (catElement == null)
	{
		this.domain = null;
		this.value = null;
	}
	else
	{
		this.domain = catElement.getAttribute("domain");
		this.value = catElement.childNodes[0].nodeValue;
	}
}

//object containing RSS image tag info
function RSS2Image(imgElement)
{
	if (imgElement == null)
	{
	this.url = null;
	this.link = null;
	this.width = null;
	this.height = null;
	this.description = null;
	}
	else
	{
		imgAttribs = new Array("url","title","link","width","height","description");
		for (var i=0; i<imgAttribs.length; i++)
			if (imgElement.getAttribute(imgAttribs[i]) != null)
				eval("this."+imgAttribs[i]+"=imgElement.getAttribute("+imgAttribs[i]+")");
	}
}

//object containing the parsed RSS 2.0 channel
function RSS2Channel(rssxml)
{
	//required
	this.title;
	this.link;
	this.description;

	//array of RSS2Item objects
	this.items = new Array();

	//optional vars
	this.language;
	this.copyright;
	this.managingEditor;
	this.webMaster;
	this.pubDate;
	this.lastBuildDate;
	this.generator;
	this.docs;
	this.ttl;
	this.rating;

	//optional objects
	this.category;
	this.image;

	var chanElement = rssxml.getElementsByTagName("channel")[0];
	var itemElements = rssxml.getElementsByTagName("item");

	for (var i=0; i<itemElements.length; i++)
	{
		Item = new RSS2Item(itemElements[i]);
		this.items.push(Item);
		//chanElement.removeChild(itemElements[i]);
	}

	var properties = new Array("title", "link", "description", "language", "copyright", "managingEditor", "webMaster", "pubDate", "lastBuildDate", "generator", "docs", "ttl", "rating");
	var tmpElement = null;
	for (var i=0; i<properties.length; i++)
	{
		tmpElement = chanElement.getElementsByTagName(properties[i])[0];
		if (tmpElement!= null)
			eval("this."+properties[i]+"=tmpElement.childNodes[0].nodeValue");
	}

	this.category = new RSS2Category(chanElement.getElementsByTagName("category")[0]);
	this.image = new RSS2Image(chanElement.getElementsByTagName("image")[0]);
}

//PROCESSES

//uses xmlhttpreq to get the raw rss xml
function getRSS(url)
{
try{
	//call the right constructor for the browser being used
	if (window.ActiveXObject)
		xhr = new ActiveXObject("Microsoft.XMLHTTP");
	else if (window.XMLHttpRequest)
		xhr = new XMLHttpRequest();
	else
		alert("not supported");

	//prepare the xmlhttprequest object
	xhr.open("GET",url,true);
	xhr.setRequestHeader("Cache-Control", "no-cache");
	xhr.setRequestHeader("Pragma", "no-cache");
	xhr.onreadystatechange = function() {
		if (xhr.readyState == 4)
		{
			if (xhr.status == 200)
			{
				if (xhr.responseText != null)
					processRSS(xhr.responseXML);
				else
				{
					dbg("Failed to receive RSS file from the server - file not found.");
					return false;
				}
			}
			else
				dbg("Error code " + xhr.status + " received: " + xhr.statusText);
		}
	}

	//send the request
	xhr.send(null);
	}
	catch(e){
		alert("Problem");
	}
}
function getExternalRSS(e){
if (window.ActiveXObject){
		var xmlDoc=new ActiveXObject("Microsoft.XMLDOM");
		xmlDoc.async="false";
		xmlDoc.loadXML(e.responseText);
		}
	else if (window.XMLHttpRequest){
		var parser=new DOMParser();
		var xmlDoc=parser.parseFromString(e.responseText,"text/xml");
}
	if (xmlDoc != null)
		processRSS(xmlDoc);
	else
		return false
}
//processes the received rss xml
function processRSS(rssxml)
{
	RSS = new RSS2Channel(rssxml);
	showRSS(RSS);
}

//shows the RSS content in the browser
function showRSS(RSS)
{
	var imageFormat = "<img id='chan_image' alt='{0}' width='{1}' height='{2}' src='{3}' border='0'/>";
	
	//default values for html tags used

	//populate channel data
	var properties = new Array(); // propiedades que quieren mostrarse
	for (var i=0; i<properties.length; i++)
	{
		eval("document.getElementById('chan_"+properties[i]+"').innerHTML = ''");
		curProp = eval("RSS."+properties[i]);
		if (curProp != null)
			eval("document.getElementById('chan_"+properties[i]+"').innerHTML = curProp");
	}

	//show the image
	document.getElementById("chan_image_link").innerHTML = "";
	if (RSS.image.src != null)
	{
		document.getElementById("chan_image_link").href = RSS.image.link;
		document.getElementById("chan_image_link").innerHTML = imageFormat.format(RSS.image.description,RSS.image.width,RSS.image.height,RSS.image.url);
	}

	//populate the items
	document.getElementById("chan_items").innerHTML = "";
	
	var c = (RSS.items.length < nnews)?RSS.items.length:nnews;
	if(nnews==0)
	{
		c = RSS.items.length;
	}
	for (var i=0; i<c; i++)
	{
		var title = (RSS.items[i].title == null) ? "" : RSS.items[i].title;
		var description = (RSS.items[i].description == null) ? "" : RSS.items[i].description;
		var author = (RSS.items[i].author == null) ? "" : RSS.items[i].author;
		var pubDate = (RSS.items[i].pubDate == null) ? "" : timeToHuman(RSS.items[i].pubDate);
		var link = (RSS.items[i].link == null) ? "" : RSS.items[i].link;
		item_html = itemFormat.format(title,author,description,pubDate,link);
		document.getElementById("chan_items").innerHTML += item_html;
	}

	//we're done
	//document.getElementById("chan").style.visibility = "visible";
	return true;
}
function dbg(m)
{
	var debug = true;
	if(debug){
		alert(m);			
}
}
var xhr;