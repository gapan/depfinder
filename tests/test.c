// vim:et:sta:sts=2:sw=2:ts=2:tw=79:
#include "test.h"

START_TEST(test_pkg_name_length1) {
  char *pkgname = "judy-1.0.5-x86_64-1";
  uint8_t res = pkg_name_length(pkgname);
  ck_assert_int_eq(res, 4);
}
END_TEST

START_TEST(test_pkg_name_length2) {
  char *pkgname = "xfce4-power-manager-1.4.4-x86_64-4";
  uint8_t res = pkg_name_length(pkgname);
  ck_assert_int_eq(res, 19);
}
END_TEST

START_TEST(test_pkg_name1) {
  char *pkgname = "judy-1.0.5-x86_64-1";
  char *res = pkg_name(pkgname);
  ck_assert_str_eq(res, "judy");
  free(res);
}
END_TEST

START_TEST(test_pkg_name2) {
  char *pkgname = "xfce4-power-manager-1.4.4-x86_64-4";
  char *res = pkg_name(pkgname);
  ck_assert_str_eq(res, "xfce4-power-manager");
  free(res);
}
END_TEST

START_TEST(test_pkg_name_null) {
  char *pkgname = "not-a-package";
  char *res = pkg_name(pkgname);
  ck_assert_ptr_eq(res, NULL);
}
END_TEST

START_TEST(test_file_in_fhs1) {
  bool res = file_in_fhs("usr/bin/depfinder");
  ck_assert(res == true);
}
END_TEST

START_TEST(test_file_in_fhs2) {
  bool res = file_in_fhs("etc/slapt-get/slapt-getrc");
  ck_assert(res == false);
}
END_TEST

START_TEST(test_add_ht_entry1) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  add_ht_entry(&revlog, "file1", "package1");
  HASH_FIND_STR(revlog, "file1", r);
  ck_assert_int_eq(r->count, 1);
  ck_assert_str_eq(r->packages[0], "package1");
  free_ht(&revlog);
}
END_TEST

START_TEST(test_add_ht_entry2) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  add_ht_entry(&revlog, "file1", "package1");
  HASH_FIND_STR(revlog, "file1", r);
  add_ht_entry(&revlog, "file1", "package2");
  ck_assert_int_eq(r->count, 2);
  ck_assert_str_eq(r->packages[0], "package1");
  ck_assert_str_eq(r->packages[1], "package2");
  free_ht(&revlog);
}
END_TEST

START_TEST(test_add_ht_entry3) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  add_ht_entry(&revlog, "file1", "package1");
  HASH_FIND_STR(revlog, "file2", r);
  ck_assert_ptr_eq(r, NULL);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_get_pkglog_contents1) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg = "libburn-1.4.2-x86_64-1gv";
  get_pkglog_contents(pkg, &revlog, true);
  HASH_FIND_STR(revlog, "/usr/bin/cdrskin", r);
  ck_assert_int_eq(r->count, 1);
  ck_assert_str_eq(r->packages[0], pkg);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_get_pkglog_contents2) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg = "libburn-1.4.2-x86_64-1gv";
  get_pkglog_contents(pkg, &revlog, false);
  HASH_FIND_STR(revlog, "/usr/man/man1/cdrskin.1.gz", r);
  ck_assert_int_eq(r->count, 1);
  ck_assert_str_eq(r->packages[0], pkg);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_get_pkglog_contents3) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg = "libburn-1.4.2-x86_64-1gv";
  get_pkglog_contents(pkg, &revlog, false);
  HASH_FIND_STR(revlog, "not_a_file", r);
  ck_assert_ptr_eq(r, NULL);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_get_pkglog_contents4) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg1 = "openssl-1.0.2s-x86_64-1_slack14.2";
  get_pkglog_contents(pkg1, &revlog, true);
  char *pkg2 = "openssl-solibs-1.0.2s-x86_64-1_slack14.2";
  get_pkglog_contents(pkg2, &revlog, true);
  HASH_FIND_STR(revlog, "/lib64/libssl.so.1.0.0", r);
  ck_assert_int_eq(r->count, 2);
  ck_assert_str_eq(r->packages[0],pkg1); 
  ck_assert_str_eq(r->packages[1], pkg2);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_read_var_log_pkg1) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg = "libburn-1.4.2-x86_64-1gv";
  read_var_log_pkg(&revlog, false);
  HASH_FIND_STR(revlog, "/usr/bin/cdrskin", r);
  ck_assert_int_eq(r->count, 1);
  ck_assert_str_eq(r->packages[0], pkg);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_read_var_log_pkg2) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg = "libburn-1.4.2-x86_64-1gv";
  read_var_log_pkg(&revlog, false);
  HASH_FIND_STR(revlog, "/usr/man/man1/cdrskin.1.gz", r);
  ck_assert_int_eq(r->count, 1);
  ck_assert_str_eq(r->packages[0], pkg);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_read_var_log_pkg3) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  read_var_log_pkg(&revlog, true);
  HASH_FIND_STR(revlog, "/usr/man/man1/cdrskin.1.gz", r);
  ck_assert_ptr_eq(r, NULL);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_read_var_log_pkg4) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  read_var_log_pkg(&revlog, true);
  HASH_FIND_STR(revlog, "not_a_file", r);
  ck_assert_ptr_eq(r, NULL);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_read_var_log_pkg5) {
  reverse_log_t *revlog = NULL;
  reverse_log_t *r = NULL;
  char *pkg1 = "openssl-1.0.2s-x86_64-1_slack14.2";
  char *pkg2 = "openssl-solibs-1.0.2s-x86_64-1_slack14.2";
  read_var_log_pkg(&revlog, true);
  HASH_FIND_STR(revlog, "/lib64/libssl.so.1.0.0", r);
  ck_assert_int_eq(r->count, 2);
  ck_assert_str_eq(r->packages[0],pkg1); 
  ck_assert_str_eq(r->packages[1], pkg2);
  free_ht(&revlog);
}
END_TEST

START_TEST(test_remove_dir_dots1) {
  char *s = "/usr/lib64/libX11-xcb.so.1";
  char *path = strdup(s);
  remove_dir_dots(&path);
  ck_assert_str_eq(path, "/usr/lib64/libX11-xcb.so.1");
}
END_TEST

START_TEST(test_remove_dir_dots2) {
  char *s = "/usr/lib64/../lib64/libX11-xcb.so.1";
  char *path = strdup(s);
  remove_dir_dots(&path);
  ck_assert_str_eq(path, "/usr/lib64/libX11-xcb.so.1");
}
END_TEST

START_TEST(test_remove_dir_dots3) {
  char *s = "/usr/lib64/../../usr/lib64/libX11-xcb.so.1";
  char *path = strdup(s);
  remove_dir_dots(&path);
  ck_assert_str_eq(path, "/usr/lib64/libX11-xcb.so.1");
}
END_TEST

START_TEST(test_remove_dir_dots4) {
  char *s = "/a/../a/b/c/d/e/f/../../../../../../a/b/c/d/e/f/g";
  char *path = strdup(s);
  remove_dir_dots(&path);
  ck_assert_str_eq(path, "/a/b/c/d/e/f/g");
}
END_TEST

START_TEST(test_remove_dir_dots5) {
  char *s = "/a/b/c/./d/././e/f";
  char *path = strdup(s);
  remove_dir_dots(&path);
  ck_assert_str_eq(path, "/a/b/c/d/e/f");
}
END_TEST

Suite *depfinder_suite(void) {
  Suite *s;
  TCase *tc_depfinder;

  s = suite_create("depfinder");
  tc_depfinder = tcase_create("pkg");

  tcase_add_test(tc_depfinder, test_pkg_name_length1);
  tcase_add_test(tc_depfinder, test_pkg_name_length2);
  tcase_add_test(tc_depfinder, test_pkg_name1);
  tcase_add_test(tc_depfinder, test_pkg_name2);
  tcase_add_test(tc_depfinder, test_pkg_name_null);
  tcase_add_test(tc_depfinder, test_file_in_fhs1);
  tcase_add_test(tc_depfinder, test_file_in_fhs2);
  tcase_add_test(tc_depfinder, test_add_ht_entry1);
  tcase_add_test(tc_depfinder, test_add_ht_entry2);
  tcase_add_test(tc_depfinder, test_add_ht_entry3);
  tcase_add_test(tc_depfinder, test_get_pkglog_contents1);
  tcase_add_test(tc_depfinder, test_get_pkglog_contents2);
  tcase_add_test(tc_depfinder, test_get_pkglog_contents3);
  tcase_add_test(tc_depfinder, test_get_pkglog_contents4);
  tcase_add_test(tc_depfinder, test_read_var_log_pkg1);
  tcase_add_test(tc_depfinder, test_read_var_log_pkg2);
  tcase_add_test(tc_depfinder, test_read_var_log_pkg3);
  tcase_add_test(tc_depfinder, test_read_var_log_pkg4);
  tcase_add_test(tc_depfinder, test_read_var_log_pkg5);
  tcase_add_test(tc_depfinder, test_remove_dir_dots1);
  tcase_add_test(tc_depfinder, test_remove_dir_dots2);
  tcase_add_test(tc_depfinder, test_remove_dir_dots3);
  tcase_add_test(tc_depfinder, test_remove_dir_dots4);
  tcase_add_test(tc_depfinder, test_remove_dir_dots5);
  suite_add_tcase(s, tc_depfinder);

  return s;
}

int main(void) {
  int number_failed = 0;
  Suite *s;
  SRunner *sr;

  s = depfinder_suite();
  sr = srunner_create(s);

  srunner_run_all(sr, CK_NORMAL);
  number_failed = srunner_ntests_failed(sr);
  srunner_free(sr);
  return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;

  return 0;
}
