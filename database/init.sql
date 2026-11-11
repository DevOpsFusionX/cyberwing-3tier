-- ============================================================
--  Cyberwing.pk Guestbook - Database schema
--  Yeh file MySQL container PEHLI DAAFA start hone par khud chalti hai
--  (path: /docker-entrypoint-initdb.d/)
-- ============================================================

CREATE TABLE IF NOT EXISTS messages (
  id         INT AUTO_INCREMENT PRIMARY KEY,          -- unique number, khud barhta hai
  name       VARCHAR(50)  NOT NULL,                   -- likhne wale ka naam
  message    VARCHAR(255) NOT NULL,                   -- message
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP      -- kab save hua
);

-- pehli test row taake app khali na lage
INSERT INTO messages (name, message)
VALUES ('Cyberwing', 'Khush aamdeed! Yeh meri pehli Azure 3-tier app hai.');
