const editMode = document.body.classList.contains('has-edit-mode-menu');

const triggerBtn = fragmentElement.querySelector('.masterclass-register-trigger-btn');
const modal = fragmentElement.querySelector('#sessionRegisterModal');
const confirmBtn = fragmentElement.querySelector('#teConfirmRegisterBtn');
const courseIdEl = fragmentElement.querySelector('#currentCourseId');

const backdrop = document.createElement('div');
backdrop.className = 'modal-backdrop fade show';

// Function to close/hide the modal
const closeModal = () => {
  if (document.body.contains(backdrop)) {
    document.body.removeChild(backdrop);
  }
  if (modal) {
    modal.classList.remove('show');
    setTimeout(() => {
      modal.style.display = 'none';
    }, 150);
  }
};

// Function to open/show the modal
const openModal = () => {
  if (modal) {
    modal.style.display = 'block';
    // Small timeout to allow display: block to render before adding transition class
    setTimeout(() => {
      modal.classList.add('show');
    }, 10);
    document.body.appendChild(backdrop);
  }
};

if (editMode) {
  // In Liferay's edit mode, make the modal inline and editable
  if (modal) {
    modal.style.display = 'block';
    modal.classList.remove('fade', 'modal');
    modal.classList.add('show');
  }
} else {
  // In view mode, guarantee the modal starts hidden and set up manual trigger listeners
  if (modal) {
    modal.style.display = 'none';
  }
  if (triggerBtn) {
    triggerBtn.addEventListener('click', function(e) {
      e.preventDefault();
      openModal();
    });
  }

  // Set up dismissal event listeners (Close, Cancel, and Backdrop click)
  if (modal) {
    modal.querySelectorAll('[data-dismiss="modal"]').forEach(item => {
      item.addEventListener('click', function(e) {
        e.preventDefault();
        closeModal();
      });
    });

    // Close when clicking outside of modal content (on the modal overlay backdrop)
    modal.addEventListener('click', function(e) {
      if (e.target === modal) {
        closeModal();
      }
    });
  }
}

// Set up Confirm Registration action click
if (confirmBtn) {
  confirmBtn.addEventListener('click', function() {
    // Find selected radio inside the modal
    const checkedRadio = document.querySelector('input[name="selectedSession"]:checked');
    if (checkedRadio) {
      // Parse the Course ID mapped directly to the DPT from our hidden span
      let currentCourseId = 0;
      if (courseIdEl) {
        const cleanCourseIdText = courseIdEl.textContent.trim().replace(/\D/g, '');
        currentCourseId = parseInt(cleanCourseIdText, 10) || 0;
      }
      
      // Traverse card to get its details
      const card = checkedRadio.closest('.masterclass-session-row-card');
      let sessionTitle = 'Selected Session';
      let selectedCmsSessionId = 0;
      
      if (card) {
        const titleEl = card.querySelector('.masterclass-session-title');
        if (titleEl) {
          sessionTitle = titleEl.textContent.trim();
        }
        const idEl = card.querySelector('.masterclass-session-id');
        if (idEl) {
          // Robust locale-aware parsing: strip all non-digit formatting characters (commas, periods, spaces)
          const cleanIdText = idEl.textContent.trim().replace(/\D/g, '');
          selectedCmsSessionId = parseInt(cleanIdText, 10) || 0;
        }
      }
      
      if (!selectedCmsSessionId) {
        alert('Warning: Selected session ID is empty. Please map the hidden session-id field to your Session ID field in the collection display.');
        return;
      }
      
      // Save original button state and trigger loading state
      const originalText = confirmBtn.textContent;
      confirmBtn.disabled = true;
      confirmBtn.textContent = 'Verifying Session...';
      
      // --- EXTRA STEP: Query MyCourseSession intermediate custom object ---
      // We look for the entry where 'courseSessionID' matches the selected CMS Structured Content ID
      const queryUrl = '/o/c/mycoursesessions?filter=courseSessionID eq ' + selectedCmsSessionId;
      
      fetch(queryUrl, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': Liferay.authToken  // Secure CSRF auth token
        }
      })
      .then(response => {
        if (!response.ok) {
          throw new Error('Failed to query intermediate session: Status ' + response.status);
        }
        return response.json();
      })
      .then(data => {
        const items = data.items || [];
        if (items.length > 0) {
          // Extract the actual Custom Object entry ID
          const realCustomSessionId = items[0].id;
          console.log(`Successfully resolved CMS Session ID ${selectedCmsSessionId} to Custom Object Session ID ${realCustomSessionId}`);
          
          // Construct clean enrollment payload using the REAL Custom Object Session ID and the DPT Course ID!
          const payload = {
            "enrollmentStatus": "Pending", // Match capitalized Picklist key
            "r_courseToUser_userId": parseInt(themeDisplay.getUserId(), 10),
            "r_enrollmentToCourseSession_c_myCourseSessionId": realCustomSessionId,
            "courseID": currentCourseId
          };
          
          confirmBtn.textContent = 'Enrolling...';
          
          // Call our robust global helper to POST the enrollment and display Toast alerts!
          LiferayService.post('/o/c/mycourseenrollments', payload);
          
          // Restore button state and close modal
          setTimeout(() => {
            confirmBtn.disabled = false;
            confirmBtn.textContent = originalText;
            closeModal();
          }, 500);
          
        } else {
          throw new Error(`Session ID ${selectedCmsSessionId} is not linked to any registered MyCourseSession entry. Please contact your administrator.`);
        }
      })
      .catch(error => {
        alert('Error: ' + error.message);
        confirmBtn.disabled = false;
        confirmBtn.textContent = originalText;
      });
      
    } else {
      alert('Please select a session before confirming your registration.');
    }
  });
}
