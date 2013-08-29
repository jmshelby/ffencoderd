<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:template match="/">
<html>
<body style="margin:0px;padding:0px;font-family:tahoma">
<table border="0" cellpadding="0" cellspacing="0" style="text-align:center;">
<tr bgcolor="#888a85" style="color:#ffffff;font-size:11px;font-weight:bold;">
<th>ID</th>
<th>Original filename</th>
<th>Source</th>
<th>Size (WxH)</th>
<th>Format</th>
<th>Resources</th>
<td>Description</td>
</tr>
<xsl:for-each select="ffencoderd/video">
<tr style="text-align:left;">
<td bgcolor="#888a85" style="color:#ffffff;text-align:center;"><xsl:value-of select="@id"/></td>
<td><xsl:value-of select="filename"/></td>
<td style="font-size:10px;padding:3px;"><xsl:value-of select="@source"/></td>
<td><xsl:value-of select="size"/></td>
<td><xsl:value-of select="format"/></td>
<td><xsl:value-of select="@source"/>/thumbnail.jpg<br/><xsl:value-of select="@source"/>/video.<xsl:value-of select="format"/></td>
<td><xsl:value-of select="description"/></td>
</tr>
</xsl:for-each>
</table>
</body>
</html>
</xsl:template>
</xsl:stylesheet>