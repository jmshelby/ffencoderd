/**
 * @fileoverview
 * Se encuentran varias funciones en este archivo que son de uso general en el sitio.
 * Las funciones han sido desarroladas por terceros o se han modificado de ya exsitentes
 * para cumplir los requisitos.
 * 
 */
 // {{{ timeToHuman
/**
* funcion devolviendo una cadena segun una marca de tiempo UNIX. La cadena devuelta es de la forma
* dd/mm/aaaa hh:mm
* @param integer t timestamp UNIX
* @return string Cadena de caracteres formando una fecha con formato dd/mm/aaaa hh:mm
*/
function timeToHuman(t)
{
    var theDate = new Date(t);
    var dateString = theDate.toGMTString();
    var arrDateStr = dateString.split(" ");
    var dataArray = new Array();
    var i10nMon = {'Jan':'Ene','Feb':'Feb','May':'May','Apr':'Abr','Mar':'Mar','Jun':'Jun','Jul':'Jul','Aug':'Ago','Sep':'Sep','Oct':'Oct','Nov':'Nov','Dec':'Dic'};
    dataArray['mon'] = i10nMon[arrDateStr[2]];
    dataArray['day'] = arrDateStr[1];
    dataArray['year'] = arrDateStr[3];
    dataArray['hr'] = arrDateStr[4].substr(0,2);
    dataArray['min'] = arrDateStr[4].substr(3,2);
    dataArray['sec'] = arrDateStr[4].substr(6,2);
    var formattedDate = dataArray['day']+"/"+dataArray['mon']+"/"+dataArray['year'];
    return formattedDate;
}
//}}}
// {{{ format
/**
* Devuelve la cadena formateada con los argumentos tal como 
* 'hola {0} a {1}'.format(arg1,arg2)
*  @param	arguments	inserta los argumentos en la posicion en que aparecen
*  @return	string	cadena formateada
*/
 String.prototype.format = function()
{
	var str = this;
    for(var i=0;i<arguments.length;i++)
    {
        var re = new RegExp('\\{' + (i) + '\\}','gm');
        str = str.replace(re, arguments[i]);

    }
    return str;
}
//}}}
