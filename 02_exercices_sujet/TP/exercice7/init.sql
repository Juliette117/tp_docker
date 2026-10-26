CREATE DATABASE IF NOT EXISTS kennelDB
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE kennelDB;

CREATE TABLE clients (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    date_naissance DATE NOT NULL,
    pseudonyme VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE adresses (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    numero VARCHAR(10) NOT NULL,
    rue VARCHAR(255) NOT NULL,
    code_postal VARCHAR(10) NOT NULL,
    commune VARCHAR(150) NOT NULL
);

CREATE TABLE clients_adresses (
    client_id INT UNSIGNED NOT NULL,
    adresse_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (client_id, adresse_id),
    CONSTRAINT fk_client_adresse_client
        FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE,
    CONSTRAINT fk_client_adresse_adresse
        FOREIGN KEY (adresse_id) REFERENCES adresses(id) ON DELETE CASCADE
);

CREATE TABLE chiens (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    date_naissance DATE NOT NULL,
    race VARCHAR(100) NOT NULL,
    sterilise BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE chats (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    date_naissance DATE NOT NULL,
    race VARCHAR(100) NOT NULL,
    sterilise BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO clients (nom, prenom, date_naissance, pseudonyme) VALUES
    ('Martin', 'Alice', '1992-04-12', 'alice92'),
    ('Bernard', 'Lucas', '1987-09-25', 'lucky87');

INSERT INTO adresses (numero, rue, code_postal, commune) VALUES
    ('12', 'rue des Lilas', '75019', 'Paris'),
    ('8B', 'avenue Victor-Hugo', '69006', 'Lyon');

INSERT INTO clients_adresses (client_id, adresse_id) VALUES
    (1, 1),
    (2, 2);

INSERT INTO chiens (nom, date_naissance, race, sterilise) VALUES
    ('Rex', '2020-05-10', 'Berger allemand', TRUE),
    ('Nala', '2022-08-03', 'Labrador', FALSE);

INSERT INTO chats (nom, date_naissance, race, sterilise) VALUES
    ('Milo', '2021-02-14', 'Européen', TRUE),
    ('Luna', '2023-06-21', 'Maine Coon', FALSE);
