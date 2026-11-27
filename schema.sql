-- LearnSphereDB: MySQL 8 schema for the LearnSphere learning platform
DROP DATABASE IF EXISTS learnsphere_db;
CREATE DATABASE learnsphere_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE learnsphere_db;

CREATE TABLE users (
  user_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(150) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('learner','admin') NOT NULL DEFAULT 'learner',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB;

CREATE TABLE courses (
  course_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title       VARCHAR(150) NOT NULL,
  description TEXT,
  level       ENUM('beginner','intermediate','advanced') NOT NULL DEFAULT 'beginner',
  is_free     TINYINT(1) NOT NULL DEFAULT 1,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (course_id),
  UNIQUE KEY uq_courses_title (title)
) ENGINE=InnoDB;

CREATE TABLE lessons (
  lesson_id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  course_id  INT UNSIGNED NOT NULL,
  lesson_no  SMALLINT UNSIGNED NOT NULL,
  title      VARCHAR(150) NOT NULL,
  video_url  VARCHAR(255),
  notes      TEXT,
  PRIMARY KEY (lesson_id),
  UNIQUE KEY uq_lessons_order (course_id, lesson_no),
  CONSTRAINT fk_lessons_course FOREIGN KEY (course_id)
    REFERENCES courses (course_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE quizzes (
  quiz_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  lesson_id INT UNSIGNED NOT NULL,
  title     VARCHAR(150) NOT NULL,
  PRIMARY KEY (quiz_id),
  UNIQUE KEY uq_quizzes_lesson (lesson_id),
  CONSTRAINT fk_quizzes_lesson FOREIGN KEY (lesson_id)
    REFERENCES lessons (lesson_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE quiz_questions (
  question_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  quiz_id        INT UNSIGNED NOT NULL,
  question_text  VARCHAR(300) NOT NULL,
  option_a       VARCHAR(200) NOT NULL,
  option_b       VARCHAR(200) NOT NULL,
  option_c       VARCHAR(200) NOT NULL,
  option_d       VARCHAR(200) NOT NULL,
  correct_option ENUM('A','B','C','D') NOT NULL,
  PRIMARY KEY (question_id),
  CONSTRAINT fk_questions_quiz FOREIGN KEY (quiz_id)
    REFERENCES quizzes (quiz_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE enrollments (
  enrollment_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id       INT UNSIGNED NOT NULL,
  course_id     INT UNSIGNED NOT NULL,
  enrolled_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (enrollment_id),
  UNIQUE KEY uq_enrollment (user_id, course_id),
  CONSTRAINT fk_enroll_user   FOREIGN KEY (user_id)   REFERENCES users (user_id)     ON DELETE CASCADE,
  CONSTRAINT fk_enroll_course FOREIGN KEY (course_id) REFERENCES courses (course_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE lesson_progress (
  user_id      INT UNSIGNED NOT NULL,
  lesson_id    INT UNSIGNED NOT NULL,
  completed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, lesson_id),
  CONSTRAINT fk_progress_user   FOREIGN KEY (user_id)   REFERENCES users (user_id)     ON DELETE CASCADE,
  CONSTRAINT fk_progress_lesson FOREIGN KEY (lesson_id) REFERENCES lessons (lesson_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE quiz_attempts (
  attempt_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      INT UNSIGNED NOT NULL,
  quiz_id      INT UNSIGNED NOT NULL,
  score        SMALLINT UNSIGNED NOT NULL,
  total        SMALLINT UNSIGNED NOT NULL,
  attempted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (attempt_id),
  KEY idx_attempts_user (user_id),
  CONSTRAINT chk_score CHECK (score <= total),
  CONSTRAINT fk_attempt_user FOREIGN KEY (user_id) REFERENCES users (user_id)   ON DELETE CASCADE,
  CONSTRAINT fk_attempt_quiz FOREIGN KEY (quiz_id) REFERENCES quizzes (quiz_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE projects (
  project_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  course_id  INT UNSIGNED NOT NULL,
  title      VARCHAR(150) NOT NULL,
  brief      TEXT,
  PRIMARY KEY (project_id),
  UNIQUE KEY uq_projects_course (course_id),
  CONSTRAINT fk_projects_course FOREIGN KEY (course_id)
    REFERENCES courses (course_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE project_submissions (
  submission_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  project_id    INT UNSIGNED NOT NULL,
  user_id       INT UNSIGNED NOT NULL,
  link_url      VARCHAR(255) NOT NULL,
  submitted_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (submission_id),
  UNIQUE KEY uq_submission (project_id, user_id),
  CONSTRAINT fk_sub_project FOREIGN KEY (project_id) REFERENCES projects (project_id) ON DELETE CASCADE,
  CONSTRAINT fk_sub_user    FOREIGN KEY (user_id)    REFERENCES users (user_id)       ON DELETE CASCADE
) ENGINE=InnoDB;

-- Audit table filled automatically by a trigger
CREATE TABLE enrollment_log (
  log_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id   INT UNSIGNED NOT NULL,
  course_id INT UNSIGNED NOT NULL,
  action    VARCHAR(20) NOT NULL,
  logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (log_id)
) ENGINE=InnoDB;

-- VIEW: progress of every learner in every enrolled course
CREATE VIEW v_course_progress AS
SELECT e.user_id,
       e.course_id,
       c.title AS course_title,
       COUNT(DISTINCT l.lesson_id)  AS total_lessons,
       COUNT(DISTINCT lp.lesson_id) AS completed_lessons,
       ROUND(100 * COUNT(DISTINCT lp.lesson_id) / NULLIF(COUNT(DISTINCT l.lesson_id), 0), 1) AS percent_complete
FROM enrollments e
JOIN courses c ON c.course_id = e.course_id
LEFT JOIN lessons l ON l.course_id = e.course_id
LEFT JOIN lesson_progress lp ON lp.lesson_id = l.lesson_id AND lp.user_id = e.user_id
GROUP BY e.user_id, e.course_id, c.title;

DELIMITER //

-- TRIGGER: record every new enrollment in the audit table
CREATE TRIGGER trg_enrollment_after_insert
AFTER INSERT ON enrollments
FOR EACH ROW
BEGIN
  INSERT INTO enrollment_log (user_id, course_id, action)
  VALUES (NEW.user_id, NEW.course_id, 'ENROLLED');
END//

-- STORED PROCEDURE: mark a lesson complete, only if the learner is enrolled in its course
CREATE PROCEDURE sp_complete_lesson(IN p_user_id INT UNSIGNED, IN p_lesson_id INT UNSIGNED)
BEGIN
  DECLARE v_course_id INT UNSIGNED;
  DECLARE v_enrolled INT DEFAULT 0;

  SELECT course_id INTO v_course_id FROM lessons WHERE lesson_id = p_lesson_id;
  IF v_course_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lesson does not exist';
  END IF;

  SELECT COUNT(*) INTO v_enrolled FROM enrollments
  WHERE user_id = p_user_id AND course_id = v_course_id;
  IF v_enrolled = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User is not enrolled in this course';
  END IF;

  INSERT IGNORE INTO lesson_progress (user_id, lesson_id) VALUES (p_user_id, p_lesson_id);
END//

DELIMITER ;
