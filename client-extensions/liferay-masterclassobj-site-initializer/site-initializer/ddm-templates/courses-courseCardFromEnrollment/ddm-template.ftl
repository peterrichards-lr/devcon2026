<style type="text/css">
.listado .bordeado {
		border-color: var(--gray-500) !important;
    border-radius: 10px !important;
    border-style: solid;
    border-width: 1px !important;
    margin-bottom: var(--spacer-3, 1rem) !important;
    padding-bottom: var(--spacer-2, 0.5rem) !important;
    padding-left: var(--spacer-2, 0.5rem) !important;
    padding-right: var(--spacer-2, 0.5rem) !important;
    padding-top: var(--spacer-2, 0.5rem) !important;
}
.listado .bordeado .imagen img{
    max-width: 100%;
}
</style>
<div class="row align-items-start listado">
<#if (ObjectEntry_objectEntryId.getData())??>
	<#assign myCourseEnrollID = ObjectEntry_objectEntryId.getData()/>
	<#assign currentUser = user.getUserId() />
	<#assign parameters="?nestedFields=myCourseSessions"/>
	<#assign myCourseEnroll = restClient.get("/c/mycourseenrollments/" + myCourseEnrollID + parameters)/>
	<#if (myCourseEnroll?has_content)>
	<#if (myCourseEnroll.r_myCourseSessionToMyCourseEnrollment_c_myCourseSessionId??)>
	<#assign currentCourseSession = myCourseEnroll.r_myCourseSessionToMyCourseEnrollment_c_myCourseSessionId />
	<#assign myCourse = restClient.get("/c/mycourses/" + myCourseEnroll.r_myCourseSessionToMyCourseEnrollment_c_myCourseSession.r_myCourseToMyCourseSession_c_myCourseId)/>
	<#if (myCourse?has_content)>
		<#if (myCourseEnroll.r_userToMyCourseEnrollment_userId==currentUser)>
		<#assign currentCourseTitle = myCourse.title />
  	<#assign currentCourseSubTitle = myCourse.shortDescription />
  	<#assign currentCourseImg = myCourse.representativeImage.link.href />
			<div class="col col-lg-4 col-sm-12 col-12 col-md-3 bordeado">
				<h3 class="component-heading display-0 mb-0 text-break">
					${currentCourseTitle}
				</h3>
				<div class="clearfix component-text-block text-break">
					${currentCourseSubTitle}
				</div>
				<div class="imagen">
					<img src="${currentCourseImg}"/>
				</div>
			</div>
			</#if>
		</#if>
		</#if>
		</#if>
</#if>
</div>