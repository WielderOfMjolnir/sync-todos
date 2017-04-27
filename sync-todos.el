;;; package --- Summary
;;; Commentary:
;;; Allows very simple synchronization between Org and Asana.

;;; Code:

(require 'org)
(require 'org-element)
(require 'asana)

(defvar st-gitlab-project-key-str "GITLAB_PROJECT_ID")
(defvar st-gitlab-task-key-str "GITLAB_TASK_ID")
(defvar st-asana-project-key-str "ASANA_PROJECT_ID")
(defvar st-asana-task-key-str "ASANA_TASK_ID")

(defun st-str-to-keyword (s)
  "Turn string S into keyword with semi-colon in front."
  (intern (concat ":" s)))

(defconst st-gitlab-project-key (st-str-to-keyword st-gitlab-project-key-str))
(defconst st-gitlab-task-key (st-str-to-keyword st-gitlab-task-key-str))
(defconst st-asana-project-key (st-str-to-keyword st-asana-project-key-str))
(defconst st-asana-task-key (st-str-to-keyword st-asana-task-key-str))


(defun st-get-all-project-headings ()
  (org-element-map (org-element-parse-buffer) 'headline
	(lambda (h)
	  (let ((asana-project-id (org-element-property st-asana-project-key h))
			(gitlab-project-id (org-element-property st-gitlab-project-key h)))
		(when (not (and (eq nil asana-project-id) (eq nil gitlab-project-id)))
		  h)))))

(defun st-gitlab-get-project-id (headline)
  (org-element-property st-gitlab-project-key headline))

(defun st-gitlab-get-task-id (headline)
  (org-element-property st-gitlab-task-key headline))

(defun st-asana-get-project-id (headline)
  (org-element-property st-asana-project-key headline))

(defun st-asana-get-task-id (headline)
  (org-element-property st-asana-task-key headline))

(defun st-org-task-remote-dep-p (el)
  "Check if EL has a remote dependency."
  (or (org-element-property st-asana-task-key el)
	  (org-element-property st-gitlab-task-key el)))

(defun st-org-get-project-tasks (project-headline)
  "Get all local tasks for project defined by PROJECT-HEADLINE."
  (org-element-map (org-element-contents project-headline) 'headline
	(lambda (h)
	  (let ((todo-type (org-element-property :todo-type h)))
		(when (not (eq nil todo-type))
		  h)))))

(defun st-asana-get-project-tasks (project-id &optional callback)
  "Get tasks for project with PROJECT-ID, optionally providing a CALLBACK."
  (asana-get
   (concat "/projects/" project-id "/tasks")
   `(("opt_fields" . "id,name,assignee_status,assignee,due_on,modified_at,created_at,completed,notes")
	 ("limit" . "100"))
   callback))

(defun st-asana-create-project-task (task-name project-id &optional description &optional completed-p)
  (asana-post "/tasks" `(("name" . ,task-name)
						 ("notes" . ,(or description ""))
						 ("assignee" . "me")
						 ("projects" . ,project-id)
						 ("completed" . ,(if completed-p
											 completed-p
										   :json-false)))
			  ;; (lambda (data)
              ;;   (let ((task-name (asana-assocdr 'name data)))
              ;;     (if task-name
              ;;         (progn
			  ;; 			(message "Created task: `%s'." task-name)
			  ;; 			data)
              ;;       (message "Unknown error: couldn't create task."))))
			  ))

(defun st-asana-due-on-to-seconds (due-on)
  "Asana return the DUE-ON field in date-only, thus we add a time to make it parsable."
  (time-to-seconds (date-to-time (concat due-on "T23:5:59.000Z"))))

(defun st-asana-due-on-to-triple (due-on)
  (when due-on
	(mapcar 'string-to-int (split-string due-on "-"))))


(defun st-asana-task-to-org (task)
  "Turn a TASK into an org-element.
A TASK is a `list' of `alist'."
  (let* ((id (int-to-string (asana-assocdr 'id task)))
		 ;; hack to get around a bug with decoding unicode
		 ;; see http://www.cnblogs.com/yangwen0228/p/6238528.html
		 ;; but that didn't work either... It get's encoded, buuut
		 ;; info is still lost and I end up with `?' for the unicode chars..
		(name (string-as-multibyte (string-as-unibyte (asana-assocdr 'name task))))
		(completed-p (asana-assocdr 'completed task))
		(status (asana-assocdr 'assignee_status task))
		(desc (string-as-multibyte (string-as-unibyte (asana-assocdr 'notes task))))
		(due-on (st-asana-due-on-to-triple (asana-assocdr 'due_on task)))
		;; create the element
		(el (if due-on
				`(headline (:title ,name
								   :level 2
								   :todo-keyword ,(if (equal completed-p :json-false)
													  "TODO"
													"DONE")
								   :todo-type ,(if (equal completed-p :json-false) 'todo 'done)
								   :deadline (timestamp (:type active
															   :year-start ,(nth 0 due-on)
															   :month-start ,(nth 1 due-on)
															   :day-start ,(nth 2 due-on)))
								   ,st-asana-task-key ,id)
						   (property-drawer nil ((node-property
												  (:key ,st-asana-task-key-str :value ,id)))))
			  `(headline (:title ,name
								 :level 2
								 :todo-keyword ,(if (equal completed-p :json-false)
													"TODO"
												  "DONE")
								 :todo-type ,(if (equal completed-p :json-false) 'todo 'done)
								 ,st-asana-task-key ,id)
						 (property-drawer nil ((node-property
												(:key ,st-asana-task-key-str :value ,id))))))))
	(when desc
	  (with-temp-buffer
		(insert desc)
		(org-element-adopt-elements el (org-element-parse-buffer))))
	el))

(defun st-asana-task-update-org (task task-headline)
  "TASK is a `list' of `alist'.
TASK-HEADLINE is an org-element, representing a TODO.
Update already existing TASK-HEADLINE with TASK, returns altered copy."
  (let ((id (asana-assocdr 'id task))
		(name (asana-assocdr 'name task))
		(new-headline (org-element-copy task-headline)))
	(org-element-put-property new-headline st-asana-task-key id)
	(org-element-put-property new-headline :title name)))

(defun st-asana-update-project-task (todo project-id)
  (let ((todo-id (org-element-property st-asana-task-key todo))
		(todo-name (org-element-property :raw-value todo))
		(todo-completed-p (eq (org-element-property :todo-type todo) 'done)))
	(asana-put (concat "/tasks/" todo-id)
			   `(("completed" . ,(or todo-completed-p :json-false))))))

(defun st-org-recursive-adopt-elements (parent children)
  "Recursively have PARENT adopt CHILDREN until empty."
  (if (not children)
	  parent
	(st-org-recursive-adopt-elements (org-element-adopt-elements parent (car children))
								 (cdr children))))

(defun st-org-get-description (el)
  "Get the description of element EL by removing prop-drawers."
  (let ((last-seen-prop-drawer nil))
	(org-element-map el 'property-drawer
	  (lambda (prop-drawer)
		(setq last-seen-prop-drawer (org-element-property :end prop-drawer))))
	(let ((desc-begin (or last-seen-prop-drawer (org-element-property :contents-begin el)))
		  (desc-end (org-element-property :contents-end el)))
	  (when (and desc-begin desc-end)
		(buffer-substring-no-properties desc-begin desc-end)))))

(defun st-org-get-asana-id (el)
  "Get the asana task id from EL, EL being a constructed element.
It seems like the way we create EL, does not guarantee the properties
to be picked up on the headline itself.
Thus, we parse the child property-node which contain the ID."
  (org-element-property st-asana-task-key el))


(defun st-org-group-by-asana-id (&rest lists)
  (let ((hash-table (make-hash-table :test #'equal)))
	(dolist (li lists hash-table)
	  (dolist (el li)
		(let ((key (st-org-get-asana-id el)))
		  (puthash key (cons el (gethash key hash-table '())) hash-table))))))

(defun st-org-resolve-todos (todos)
  (if (<= (length todos) 1)
	  (car todos)
	;; compare 1st and 2nd, drop the oldest one
	(let* ((newest (nth 0 todos))
		   (newest-todo (org-element-property :todo-type newest))
		   (candidate (nth 1 todos))
		   (candidate-todo (org-element-property :todo-type candidate))
		   (to-go (cdr (cdr todos))))
	  ;; if they're equal => return current
	  ;; otherwise we return the one that is finished
	  ;; TODO: make this depend on last modified instead
	  (if (eq newest-todo candidate-todo)
		  (st-org-resolve-todos (cons newest to-go))
		(if (eq newest-todo 'done)
			(st-org-resolve-todos (cons newest to-go))
		  (st-org-resolve-todos (cons candidate to-go)))))))

(defun st-update-project-headlines (project-headlines &optional updated-headlines)
  (if (not project-headlines)
	  ;; return updated headlines if we're done
	  updated-headlines
	;; else keep going
	(let* ((project-hl (car project-headlines))
		   (project-id (org-element-property st-asana-project-key project-hl))
		   (org-todos (st-org-get-project-tasks project-hl))
		   (tasks (when project-id (st-asana-get-project-tasks project-id))))
	  (if (or tasks org-todos)
		  ;; do updates for each task
		  (st-update-project-headlines
		   (cdr project-headlines)
		   (cons (let* ((asana-todos (mapcar 'st-asana-task-to-org tasks))
						(asana-todos-lookup (make-hash-table :test #'equal))
						(grouped (st-org-group-by-asana-id org-todos asana-todos))
						(updated-todos ()))
				   ;; populate lookup what we got from asana
				   (org-element-map asana-todos 'headline
					 (lambda (h) (puthash (st-asana-get-task-id h) h asana-todos-lookup)))
				   ;; `maphash' returns `nil', so we need to store results in `updated-todos'
				   (maphash (lambda (k vals)
							  (if (> (length vals) 1)
								  (add-to-list 'updated-todos (st-org-resolve-todos vals) t)
							    (add-to-list 'updated-todos (car vals) t)))
							grouped)
				   ;; before adopting, we need to update those already in file
				   (let ((old-org-todos (make-hash-table :test #'equal))
						 (new-todos ()))
					 ;; create lookup table for old todos
					 (dolist (old-todo org-todos)
					   (let ((old-todo-id (st-asana-get-task-id old-todo)))
						 (if old-todo-id
							 (puthash old-todo-id old-todo old-org-todos)
						   ;; in this case we need to push this local todo to remote
						   (let* ((task-name (org-element-property :raw-value old-todo))
								  ;; TODO get contents and put as description
								  (task-desc (st-org-get-description old-todo))
								  (resp-data (st-asana-create-project-task
											  task-name
											  project-id
											  task-desc
											  (eq (org-element-property :todo-type old-todo) 'done))))
							 (when resp-data
							   ;; create was successful => in-memory alteration to `old-todo'
							   (let* ((old-todo-contents (org-element-contents old-todo))
									  (old-todo-new-id (int-to-string
														(asana-assocdr 'id resp-data)))
									  (old-todo-property-drawer `(property-drawer
																  nil
																  ((node-property
																	(:key ,st-asana-task-key-str
																		  :value ,old-todo-new-id))))))
								 (org-element-put-property
								  old-todo
								  st-asana-task-key
								  old-todo-new-id)
								 (if old-todo-contents
									 (org-element-insert-before
									  old-todo-property-drawer
									  (car (org-element-contents old-todo)))
								   (org-element-adopt-elements old-todo old-todo-property-drawer))))))))
					 ;; go through new todos and replace old todos
					 (dolist (todo updated-todos)
					   (let* ((task-id (st-asana-get-task-id todo))
							  (mby-old-todo (gethash task-id old-org-todos)))
						(if mby-old-todo
							;; means we need to make an update
							(progn
							  (org-element-set-element mby-old-todo todo)
							  ;; already know `todo' is from local, so we check if asana-todo differ in todo-state
							  ;; => if it does, we update the remote version
							  (when
								  (not (eq (org-element-property :todo-type todo)
										   (org-element-property :todo-type (gethash task-id asana-todos-lookup))))
								(st-asana-update-project-task todo project-id)))
						  ;; we recognize new `todo' by not having `:parent'
						  (when (not (org-element-property :parent todo))
							  (add-to-list 'new-todos todo t)))))
					 ;; finally we add all new todos
					 (st-org-recursive-adopt-elements project-hl new-todos)))
				 updated-headlines))
		(st-update-project-headlines (cdr project-headlines) (or updated-headlines '()))))))

(defun sync-todos-current-buffer ()
  "Sync current buffer with Asana."
  (interactive)
  (let ((target-buffer (current-buffer))
		(updated-project-headlines (st-update-project-headlines (st-get-all-project-headings))))
	(with-temp-buffer
	  (insert (org-element-interpret-data updated-project-headlines))
	  (org-indent-region 0 (buffer-end 1))
	  (if (not (buffer-string))
		  (message "Buffer was empty, something went wrong.")
		(buffer-swap-text target-buffer)))))

(defun test-st-insert-to-buffer (buffer-name)
  "Test function which acts on BUFFER-NAME."
  (switch-to-buffer-other-window buffer-name)
  (goto-char (max-char))
  (insert (org-element-interpret-data
		   (org-element-map
			   (st-get-all-project-headings)
			   'headline
			 (lambda (project-hl)
			   (let* ((project-id (org-element-property st-asana-project-key project-hl))
					  (tasks (when project-id (st-asana-get-project-tasks project-id))))
				 (when tasks
				   (st-org-recursive-adopt-elements project-hl (mapcar 'st-asana-task-to-org tasks)))))))))

;; 1. get all local project headings
;; 2. get all remote project tasks
;; 2. merge local and remote
;; 3. for all local without asana-id, create from :title and (org-element-property el st-asana-project-task-key)
;; 4. for all pairs of local & remote
;;   if local > remote => push update to remote
;;   else (org-element-set-element remote-el)

(provide 'sync-todos)
;;; sync-todos.el ends here
