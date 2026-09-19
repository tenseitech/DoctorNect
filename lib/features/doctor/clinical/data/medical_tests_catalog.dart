/// Catalog of lab tests, radiology investigations, and body parts.
/// Used by the prescription investigations multi-select picker.
class TestCatalogItem {
  const TestCatalogItem({
    required this.id,
    required this.name,
    required this.group,
  });

  final String id;
  final String name;
  final String group;
}

abstract final class MedicalTestsCatalog {
  // -----------------------------------------------------------------
  // LAB TESTS
  // -----------------------------------------------------------------
  static const labTests = <TestCatalogItem>[
    // HAEMATOLOGY
    TestCatalogItem(
        id: 'lab_cbc',
        name: 'Complete Blood Count (CBC)',
        group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_esr',
        name: 'ESR (Erythrocyte Sedimentation Rate)',
        group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_pbs', name: 'Peripheral Blood Smear', group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_retic', name: 'Reticulocyte Count', group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_bt', name: 'Bleeding Time (BT)', group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_ct', name: 'Clotting Time (CT)', group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_pt', name: 'Prothrombin Time (PT)', group: 'Haematology'),
    TestCatalogItem(id: 'lab_inr', name: 'INR', group: 'Haematology'),
    TestCatalogItem(
        id: 'lab_aptt',
        name: 'aPTT (Activated Partial Thromboplastin Time)',
        group: 'Haematology'),

    // BIOCHEMISTRY
    TestCatalogItem(
        id: 'lab_bsf', name: 'Blood Sugar Fasting', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_bspp',
        name: 'Blood Sugar Post Prandial (PP)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_bsr', name: 'Blood Sugar Random', group: 'Biochemistry'),
    TestCatalogItem(id: 'lab_hba1c', name: 'HbA1c', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_lft',
        name: 'LFT (Liver Function Test)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_rft',
        name: 'RFT / KFT (Renal / Kidney Function Test)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_lipid', name: 'Lipid Profile', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_electrolytes',
        name: 'Serum Electrolytes (Na / K / Cl)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_uric_acid', name: 'Serum Uric Acid', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_calcium', name: 'Serum Calcium', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_phosphorus', name: 'Serum Phosphorus', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_albumin', name: 'Serum Albumin', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_bilirubin',
        name: 'Serum Bilirubin (Total / Direct / Indirect)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_amylase', name: 'Serum Amylase', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_lipase', name: 'Serum Lipase', group: 'Biochemistry'),
    TestCatalogItem(id: 'lab_iron', name: 'Serum Iron', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_tibc',
        name: 'TIBC (Total Iron Binding Capacity)',
        group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_ferritin', name: 'Serum Ferritin', group: 'Biochemistry'),
    TestCatalogItem(
        id: 'lab_total_protein',
        name: 'Serum Protein (Total)',
        group: 'Biochemistry'),

    // THYROID
    TestCatalogItem(
        id: 'lab_tsh',
        name: 'TSH (Thyroid Stimulating Hormone)',
        group: 'Thyroid'),
    TestCatalogItem(
        id: 'lab_t3', name: 'T3 (Triiodothyronine)', group: 'Thyroid'),
    TestCatalogItem(id: 'lab_t4', name: 'T4 (Thyroxine)', group: 'Thyroid'),
    TestCatalogItem(id: 'lab_ft3', name: 'Free T3', group: 'Thyroid'),
    TestCatalogItem(id: 'lab_ft4', name: 'Free T4', group: 'Thyroid'),
    TestCatalogItem(
        id: 'lab_anti_tpo', name: 'Anti-TPO Antibody', group: 'Thyroid'),

    // CARDIAC MARKERS
    TestCatalogItem(
        id: 'lab_trop_i', name: 'Troponin I', group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_trop_t', name: 'Troponin T', group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_ckmb',
        name: 'CK-MB (Creatine Kinase-MB)',
        group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_ldh',
        name: 'LDH (Lactate Dehydrogenase)',
        group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_bnp',
        name: 'BNP (Brain Natriuretic Peptide)',
        group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_nt_probnp', name: 'NT-proBNP', group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_d_dimer', name: 'D-Dimer', group: 'Cardiac Markers'),
    TestCatalogItem(
        id: 'lab_homocysteine', name: 'Homocysteine', group: 'Cardiac Markers'),

    // LIVER / HEPATITIS
    TestCatalogItem(
        id: 'lab_hbsag',
        name: 'HBsAg (Hepatitis B Surface Antigen)',
        group: 'Liver / Hepatitis'),
    TestCatalogItem(
        id: 'lab_anti_hcv',
        name: 'Anti-HCV (Hepatitis C Antibody)',
        group: 'Liver / Hepatitis'),
    TestCatalogItem(
        id: 'lab_hep_a_igm',
        name: 'Hepatitis A IgM',
        group: 'Liver / Hepatitis'),
    TestCatalogItem(
        id: 'lab_hep_e_igm',
        name: 'Hepatitis E IgM',
        group: 'Liver / Hepatitis'),

    // DIABETES / HORMONES
    TestCatalogItem(
        id: 'lab_insulin_fasting',
        name: 'Insulin Fasting',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_c_peptide', name: 'C-Peptide', group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_homa_ir', name: 'HOMA-IR', group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_cortisol_am',
        name: 'Cortisol Morning',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_cortisol_pm',
        name: 'Cortisol Evening',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_prolactin', name: 'Prolactin', group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_fsh',
        name: 'FSH (Follicle Stimulating Hormone)',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_lh',
        name: 'LH (Luteinizing Hormone)',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_estrogen',
        name: 'Estrogen (Estradiol)',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_progesterone',
        name: 'Progesterone',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_testosterone',
        name: 'Testosterone (Total)',
        group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_dheas', name: 'DHEA-S', group: 'Diabetes / Hormones'),
    TestCatalogItem(
        id: 'lab_amh',
        name: 'AMH (Anti-Mullerian Hormone)',
        group: 'Diabetes / Hormones'),

    // INFECTION / IMMUNITY
    TestCatalogItem(
        id: 'lab_crp',
        name: 'CRP (C-Reactive Protein)',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_procalcitonin',
        name: 'Procalcitonin',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_widal', name: 'Widal Test', group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_malaria',
        name: 'Malaria Antigen (MP Antigen)',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_dengue_ns1',
        name: 'Dengue NS1 Antigen',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_dengue_igm',
        name: 'Dengue IgM',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_dengue_igg',
        name: 'Dengue IgG',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_hiv', name: 'HIV 1 & 2', group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_vdrl', name: 'VDRL (Syphilis)', group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_rpr', name: 'RPR (Syphilis)', group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_ana',
        name: 'ANA (Antinuclear Antibody)',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_anti_dsdna',
        name: 'Anti-dsDNA',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_ra_factor',
        name: 'RA Factor (Rheumatoid Arthritis Factor)',
        group: 'Infection / Immunity'),
    TestCatalogItem(
        id: 'lab_aso',
        name: 'ASO Titre (Anti-Streptolysin O)',
        group: 'Infection / Immunity'),

    // URINE TESTS
    TestCatalogItem(
        id: 'lab_urine_routine',
        name: 'Urine Routine & Microscopy',
        group: 'Urine'),
    TestCatalogItem(
        id: 'lab_urine_culture',
        name: 'Urine Culture & Sensitivity',
        group: 'Urine'),
    TestCatalogItem(
        id: 'lab_urine_24hr_protein',
        name: '24hr Urine Protein',
        group: 'Urine'),
    TestCatalogItem(
        id: 'lab_urine_microalbumin',
        name: 'Urine Microalbumin',
        group: 'Urine'),
    TestCatalogItem(
        id: 'lab_urine_creatinine', name: 'Urine Creatinine', group: 'Urine'),
    TestCatalogItem(
        id: 'lab_upt', name: 'Urine Pregnancy Test (UPT)', group: 'Urine'),

    // STOOL TESTS
    TestCatalogItem(
        id: 'lab_stool_routine',
        name: 'Stool Routine & Microscopy',
        group: 'Stool'),
    TestCatalogItem(
        id: 'lab_stool_culture',
        name: 'Stool Culture & Sensitivity',
        group: 'Stool'),
    TestCatalogItem(
        id: 'lab_stool_occult',
        name: 'Stool Occult Blood Test',
        group: 'Stool'),

    // CANCER MARKERS
    TestCatalogItem(
        id: 'lab_psa',
        name: 'PSA (Prostate Specific Antigen)',
        group: 'Cancer Markers'),
    TestCatalogItem(
        id: 'lab_ca125',
        name: 'CA-125 (Ovarian Cancer Marker)',
        group: 'Cancer Markers'),
    TestCatalogItem(
        id: 'lab_ca19_9',
        name: 'CA 19-9 (Pancreatic Cancer Marker)',
        group: 'Cancer Markers'),
    TestCatalogItem(
        id: 'lab_cea',
        name: 'CEA (Carcinoembryonic Antigen)',
        group: 'Cancer Markers'),
    TestCatalogItem(
        id: 'lab_afp',
        name: 'AFP (Alpha-Fetoprotein)',
        group: 'Cancer Markers'),
    TestCatalogItem(
        id: 'lab_beta_hcg', name: 'Beta-HCG', group: 'Cancer Markers'),

    // VITAMINS & MINERALS
    TestCatalogItem(
        id: 'lab_vit_d',
        name: 'Vitamin D (25-OH)',
        group: 'Vitamins & Minerals'),
    TestCatalogItem(
        id: 'lab_vit_b12', name: 'Vitamin B12', group: 'Vitamins & Minerals'),
    TestCatalogItem(
        id: 'lab_folate',
        name: 'Folate / Folic Acid',
        group: 'Vitamins & Minerals'),
    TestCatalogItem(id: 'lab_zinc', name: 'Zinc', group: 'Vitamins & Minerals'),
    TestCatalogItem(
        id: 'lab_magnesium', name: 'Magnesium', group: 'Vitamins & Minerals'),

    // MICROBIOLOGY / CULTURE
    TestCatalogItem(
        id: 'lab_blood_culture',
        name: 'Blood Culture & Sensitivity',
        group: 'Microbiology / Culture'),
    TestCatalogItem(
        id: 'lab_sputum_culture',
        name: 'Sputum Culture & Sensitivity',
        group: 'Microbiology / Culture'),
    TestCatalogItem(
        id: 'lab_throat_swab',
        name: 'Throat Swab Culture',
        group: 'Microbiology / Culture'),
    TestCatalogItem(
        id: 'lab_wound_swab',
        name: 'Wound Swab Culture & Sensitivity',
        group: 'Microbiology / Culture'),
  ];

  // -----------------------------------------------------------------
  // RADIOLOGY
  // -----------------------------------------------------------------
  static const radiologyTests = <TestCatalogItem>[
    // X-RAY
    TestCatalogItem(
        id: 'rad_xr_chest_pa', name: 'X-Ray Chest PA View', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_chest_ap', name: 'X-Ray Chest AP View', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_abd_erect', name: 'X-Ray Abdomen Erect', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_abd_supine', name: 'X-Ray Abdomen Supine', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_cspine', name: 'X-Ray Cervical Spine', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_tspine', name: 'X-Ray Thoracic Spine', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_lspine', name: 'X-Ray Lumbar Spine', group: 'X-Ray'),
    TestCatalogItem(id: 'rad_xr_pelvis', name: 'X-Ray Pelvis', group: 'X-Ray'),
    TestCatalogItem(id: 'rad_xr_skull', name: 'X-Ray Skull', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_knee_l', name: 'X-Ray Knee (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_knee_r', name: 'X-Ray Knee (Right)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_shoulder_l', name: 'X-Ray Shoulder (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_shoulder_r',
        name: 'X-Ray Shoulder (Right)',
        group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_ankle_l', name: 'X-Ray Ankle (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_ankle_r', name: 'X-Ray Ankle (Right)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_wrist_l', name: 'X-Ray Wrist (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_wrist_r', name: 'X-Ray Wrist (Right)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_hand_l', name: 'X-Ray Hand (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_hand_r', name: 'X-Ray Hand (Right)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_foot_l', name: 'X-Ray Foot (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_foot_r', name: 'X-Ray Foot (Right)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_elbow_l', name: 'X-Ray Elbow (Left)', group: 'X-Ray'),
    TestCatalogItem(
        id: 'rad_xr_elbow_r', name: 'X-Ray Elbow (Right)', group: 'X-Ray'),

    // USG
    TestCatalogItem(
        id: 'rad_usg_abd_pelvis',
        name: 'USG Abdomen & Pelvis',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_whole_abd',
        name: 'USG Whole Abdomen',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_upper_abd',
        name: 'USG Upper Abdomen',
        group: 'Ultrasound'),
    TestCatalogItem(id: 'rad_usg_neck', name: 'USG Neck', group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_thyroid', name: 'USG Thyroid', group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_breast_l', name: 'USG Breast (Left)', group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_breast_r',
        name: 'USG Breast (Right)',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_breast_both',
        name: 'USG Breast (Both)',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_scrotum', name: 'USG Scrotum', group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_obs_dating',
        name: 'USG Obstetric — Dating Scan',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_obs_anomaly',
        name: 'USG Obstetric — Anomaly Scan',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_obs_growth',
        name: 'USG Obstetric — Growth Scan',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_dop_carotid',
        name: 'USG Doppler — Carotid',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_dop_peripheral',
        name: 'USG Doppler — Peripheral',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_dop_renal',
        name: 'USG Doppler — Renal',
        group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_fnac', name: 'USG Guided FNAC', group: 'Ultrasound'),
    TestCatalogItem(
        id: 'rad_usg_biopsy', name: 'USG Guided Biopsy', group: 'Ultrasound'),

    // CT SCAN
    TestCatalogItem(
        id: 'rad_ct_brain_plain', name: 'CT Brain Plain', group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_brain_contrast',
        name: 'CT Brain Contrast',
        group: 'CT Scan'),
    TestCatalogItem(id: 'rad_ct_chest', name: 'CT Chest', group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_abd_pelvis', name: 'CT Abdomen & Pelvis', group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_cspine', name: 'CT Cervical Spine', group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_lspine', name: 'CT Lumbar Spine', group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_angio_coronary',
        name: 'CT Angiography — Coronary',
        group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_angio_pulm',
        name: 'CT Angiography — Pulmonary',
        group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_angio_periph',
        name: 'CT Angiography — Peripheral',
        group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_hrct_chest',
        name: 'HRCT Chest (High Resolution CT)',
        group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_kub',
        name: 'CT KUB (Kidney-Ureter-Bladder)',
        group: 'CT Scan'),
    TestCatalogItem(
        id: 'rad_ct_pns', name: 'CT Paranasal Sinuses (PNS)', group: 'CT Scan'),

    // MRI
    TestCatalogItem(
        id: 'rad_mri_brain_plain', name: 'MRI Brain Plain', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_brain_contrast', name: 'MRI Brain Contrast', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_cspine', name: 'MRI Cervical Spine', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_lspine', name: 'MRI Lumbar Spine', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_tspine', name: 'MRI Thoracic Spine', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_knee_l', name: 'MRI Knee (Left)', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_knee_r', name: 'MRI Knee (Right)', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_shoulder_l', name: 'MRI Shoulder (Left)', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_shoulder_r', name: 'MRI Shoulder (Right)', group: 'MRI'),
    TestCatalogItem(id: 'rad_mri_abd', name: 'MRI Abdomen', group: 'MRI'),
    TestCatalogItem(id: 'rad_mri_pelvis', name: 'MRI Pelvis', group: 'MRI'),
    TestCatalogItem(id: 'rad_mri_breast', name: 'MRI Breast', group: 'MRI'),
    TestCatalogItem(id: 'rad_mra', name: 'MRI Angiography (MRA)', group: 'MRI'),
    TestCatalogItem(
        id: 'rad_mri_fistulogram', name: 'MRI Fistulogram', group: 'MRI'),

    // NUCLEAR MEDICINE
    TestCatalogItem(
        id: 'rad_pet_ct',
        name: 'PET CT Scan (Whole Body)',
        group: 'Nuclear Medicine'),
    TestCatalogItem(
        id: 'rad_bone_scan', name: 'Bone Scan', group: 'Nuclear Medicine'),
    TestCatalogItem(
        id: 'rad_thyroid_scan',
        name: 'Thyroid Scan',
        group: 'Nuclear Medicine'),
    TestCatalogItem(
        id: 'rad_dexa',
        name: 'DEXA Scan (Bone Density)',
        group: 'Nuclear Medicine'),
    TestCatalogItem(
        id: 'rad_vq',
        name: 'VQ Scan (Lung Perfusion)',
        group: 'Nuclear Medicine'),

    // SPECIAL PROCEDURES
    TestCatalogItem(
        id: 'rad_mammo', name: 'Mammography', group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_opg',
        name: 'OPG (Dental Panoramic X-Ray)',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_barium_swallow',
        name: 'Barium Swallow',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_barium_meal',
        name: 'Barium Meal',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_barium_enema',
        name: 'Barium Enema',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_ivp',
        name: 'IVP (Intravenous Pyelogram)',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_hsg',
        name: 'HSG (Hysterosalpingography)',
        group: 'Special Procedures'),
    TestCatalogItem(
        id: 'rad_fluoro', name: 'Fluoroscopy', group: 'Special Procedures'),

    // CARDIOLOGY
    TestCatalogItem(
        id: 'rad_ecg', name: 'ECG / EKG (12 Lead)', group: 'Cardiology'),
    TestCatalogItem(
        id: 'rad_2d_echo',
        name: '2D Echo (Echocardiography)',
        group: 'Cardiology'),
    TestCatalogItem(
        id: 'rad_holter',
        name: 'Holter Monitor (24hr ECG)',
        group: 'Cardiology'),
    TestCatalogItem(
        id: 'rad_tmt',
        name: 'Treadmill Test (TMT / Stress Test)',
        group: 'Cardiology'),
    TestCatalogItem(
        id: 'rad_coronary_angio',
        name: 'Coronary Angiography',
        group: 'Cardiology'),

    // ENDOSCOPY
    TestCatalogItem(
        id: 'rad_ugi_endo',
        name: 'Upper GI Endoscopy (OGD Scope)',
        group: 'Endoscopy'),
    TestCatalogItem(
        id: 'rad_colonoscopy', name: 'Colonoscopy', group: 'Endoscopy'),
    TestCatalogItem(
        id: 'rad_sigmoidoscopy', name: 'Sigmoidoscopy', group: 'Endoscopy'),
    TestCatalogItem(
        id: 'rad_bronchoscopy', name: 'Bronchoscopy', group: 'Endoscopy'),
    TestCatalogItem(
        id: 'rad_cystoscopy', name: 'Cystoscopy', group: 'Endoscopy'),
    TestCatalogItem(
        id: 'rad_colposcopy', name: 'Colposcopy', group: 'Endoscopy'),
  ];

  // -----------------------------------------------------------------
  // BODY PARTS / REGIONS
  // -----------------------------------------------------------------
  static const bodyParts = <String>[
    'Head / Skull',
    'Brain',
    'Eyes / Orbit',
    'Ears',
    'Nose / Sinuses (PNS)',
    'Throat',
    'Neck',
    'Thyroid',
    'Chest / Lungs',
    'Heart',
    'Breast (Left)',
    'Breast (Right)',
    'Breast (Both)',
    'Liver',
    'Gallbladder',
    'Pancreas',
    'Spleen',
    'Kidneys (Left)',
    'Kidneys (Right)',
    'Kidneys (Both)',
    'Adrenal Glands',
    'Urinary Bladder',
    'Uterus',
    'Ovaries (Left)',
    'Ovaries (Right)',
    'Ovaries (Both)',
    'Prostate',
    'Abdomen (Whole)',
    'Pelvis',
    'Cervical Spine',
    'Thoracic Spine',
    'Lumbar Spine',
    'Shoulder (Left)',
    'Shoulder (Right)',
    'Elbow (Left)',
    'Elbow (Right)',
    'Wrist (Left)',
    'Wrist (Right)',
    'Hand / Fingers (Left)',
    'Hand / Fingers (Right)',
    'Hip (Left)',
    'Hip (Right)',
    'Knee (Left)',
    'Knee (Right)',
    'Ankle (Left)',
    'Ankle (Right)',
    'Foot / Toes (Left)',
    'Foot / Toes (Right)',
    'Skin / Soft Tissue',
    'Lymph Nodes',
    'Peripheral Vessels',
    'Scrotum / Testes',
    'Rectum / Anus',
    'Peripheral Nerves',
  ];

  // -----------------------------------------------------------------
  // TEMPLATES — frequently used combinations (test ids)
  // -----------------------------------------------------------------
  static const templates = <String, List<String>>{
    'Diabetes Panel': [
      'lab_bsf',
      'lab_bspp',
      'lab_hba1c',
      'lab_lipid',
      'lab_rft',
      'lab_urine_microalbumin',
    ],
    'Thyroid Panel': [
      'lab_tsh',
      'lab_t3',
      'lab_t4',
      'lab_ft3',
      'lab_ft4',
      'lab_anti_tpo',
    ],
    'Fever Panel': [
      'lab_cbc',
      'lab_malaria',
      'lab_dengue_ns1',
      'lab_widal',
      'lab_urine_routine',
      'lab_crp',
    ],
    'Cardiac Workup': [
      'lab_trop_i',
      'lab_ckmb',
      'lab_d_dimer',
      'rad_ecg',
      'rad_2d_echo',
    ],
    'Anaemia Workup': [
      'lab_cbc',
      'lab_pbs',
      'lab_iron',
      'lab_ferritin',
      'lab_tibc',
      'lab_vit_b12',
      'lab_folate',
    ],
    'Liver Workup': [
      'lab_lft',
      'lab_hbsag',
      'lab_anti_hcv',
      'rad_usg_upper_abd',
    ],
  };

  static TestCatalogItem? labById(String id) {
    for (final t in labTests) {
      if (t.id == id) return t;
    }
    return null;
  }

  static TestCatalogItem? radiologyById(String id) {
    for (final t in radiologyTests) {
      if (t.id == id) return t;
    }
    return null;
  }

  static TestCatalogItem? findById(String id) {
    return labById(id) ?? radiologyById(id);
  }
}
