<#if (ObjectField_representativeImage.getData())??>
	<#assign mydocID=ObjectField_representativeImage.getData()/>
	<#assign myImage = restClient.get("/headless-delivery/v1.0/documents/" + mydocID)/>
	<#if myImage??>
		<img src="${myImage.contentUrl}">
	</#if>
</#if>