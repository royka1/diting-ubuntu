#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "acdb.h"

static void init(const char *f)
{
	AcdbDataFiles files = {0};
	AcdbFile delta = {0};
	files.num_files = 1;
	strcpy(files.acdbFiles[0].fileName, f);
	files.acdbFiles[0].fileNameLen = strlen(f);
	int r = acdb_init(&files, &delta);
	if (r) { fprintf(stderr, "acdb_init %d\n", r); exit(1); }
}

static void gkvs(int argc, char **argv)
{
	uint32_t keys[32]; AcdbUintList in = { argc, keys };
	for (int i = 0; i < argc; i++) keys[i] = strtoul(argv[i], 0, 0);
	AcdbKeyVectorList out = {0};
	int r = acdb_ioctl(ACDB_CMD_GET_SUPPORTED_GKVS, &in, sizeof(in), &out, sizeof(out));
	if (r) { printf("size query %d\n", r); return; }
	out.key_vector_list = malloc(out.list_size);
	r = acdb_ioctl(ACDB_CMD_GET_SUPPORTED_GKVS, &in, sizeof(in), &out, sizeof(out));
	if (r) { printf("query %d\n", r); return; }
	uint32_t *p = (uint32_t *)out.key_vector_list;
	for (uint32_t i = 0; i < out.num_key_vectors; i++) {
		uint32_t n = *p++;
		for (uint32_t k = 0; k < n; k++, p += 2) printf("%08x=%08x ", p[0], p[1]);
		printf("\n");
	}
}


static AcdbKeyValuePair kvs[32];
static int parse_kv(int argc, char **argv)
{
	for (int i = 0; i < argc; i++) {
		kvs[i].key = strtoul(argv[i], 0, 16);
		kvs[i].value = strtoul(strchr(argv[i], '=') + 1, 0, 16);
	}
	return argc;
}

static void dumpf(const char *name, void *buf, uint32_t size)
{
	FILE *f = fopen(name, "wb"); fwrite(buf, 1, size, f); fclose(f);
}

/* graph KV... : subgraphs + dsts, then per-subgraph spf blob + driver props, connections */
static void graph(int argc, char **argv)
{
	AcdbGraphKeyVector gkv = { parse_kv(argc, argv), kvs };
	AcdbGetGraphRsp g = {0};
	int r = acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &g, sizeof(g));
	if (r) { printf("graph size %d\n", r); return; }
	g.subgraphs = malloc(g.size);
	r = acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &g, sizeof(g));
	if (r) { printf("graph %d\n", r); return; }
	uint32_t *p = (uint32_t *)g.subgraphs, sgs[64];
	for (uint32_t i = 0; i < g.num_subgraphs; i++) {
		sgs[i] = p[0];
		printf("SG %08x ->", p[0]);
		for (uint32_t d = 0; d < p[1]; d++) printf(" %08x", p[2 + d]);
		printf("\n");
		p += 2 + p[1];
	}
	for (uint32_t i = 0; i < g.num_subgraphs; i++) {
		AcdbSgIdGraphKeyVector in = { 1, &sgs[i], gkv };
		AcdbGetSubgraphDataRsp d = {0};
		r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_DATA, &in, sizeof(in), &d, sizeof(d));
		if (r) { printf("sgdata size %08x: %d\n", sgs[i], r); continue; }
		d.driver_prop.sub_graph_prop_data = malloc(d.driver_prop.size);
		d.spf_blob.buf = malloc(d.spf_blob.buf_size);
		r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_DATA, &in, sizeof(in), &d, sizeof(d));
		if (r) { printf("sgdata %08x: %d\n", sgs[i], r); continue; }
		char n[64];
		sprintf(n, "sg_%08x.spf", sgs[i]); dumpf(n, d.spf_blob.buf, d.spf_blob.buf_size);
		sprintf(n, "sg_%08x.drv", sgs[i]); dumpf(n, d.driver_prop.sub_graph_prop_data, d.driver_prop.size);
	}
	AcdbSubGraphList l = { g.num_subgraphs, g.subgraphs };
	AcdbBlob b = {0};
	r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CONNECTIONS, &l, sizeof(l), &b, sizeof(b));
	if (r) { printf("conn size %d\n", r); return; }
	b.buf = malloc(b.buf_size);
	r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CONNECTIONS, &l, sizeof(l), &b, sizeof(b));
	if (r) { printf("conn %d\n", r); return; }
	dumpf("conn.spf", b.buf, b.buf_size);
}


static AcdbKeyValuePair ckv[32];
static int nckv;
static void parse_ckv(const char *e)
{
	char buf[512]; strncpy(buf, e ? e : "", sizeof(buf) - 1);
	nckv = 0;
	for (char *t = strtok(buf, ","); t; t = strtok(NULL, ",")) {
		ckv[nckv].key = strtoul(t, 0, 16);
		ckv[nckv].value = strtoul(strchr(t, '=') + 1, 0, 16);
		nckv++;
	}
}

/* cal KV... : list CKVs of the graph; with env CKV="k=v,..." dump cal for each SG */
static void cal(int argc, char **argv)
{
	AcdbGraphKeyVector gkv = { parse_kv(argc, argv), kvs };
	AcdbKeyVectorList out = {0};
	int r = acdb_ioctl(ACDB_CMD_GET_GRAPH_CAL_KVS, &gkv, sizeof(gkv), &out, sizeof(out));
	if (!r) {
		out.key_vector_list = malloc(out.list_size);
		r = acdb_ioctl(ACDB_CMD_GET_GRAPH_CAL_KVS, &gkv, sizeof(gkv), &out, sizeof(out));
		uint32_t *p = (uint32_t *)out.key_vector_list;
		for (uint32_t i = 0; !r && i < out.num_key_vectors; i++) {
			uint32_t n = *p++;
			printf("CKV:");
			for (uint32_t k = 0; k < n; k++, p += 2) printf(" %08x=%08x", p[0], p[1]);
			printf("\n");
		}
	} else printf("cal kvs %d\n", r);

	AcdbGetGraphRsp g = {0};
	acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &g, sizeof(g));
	g.subgraphs = malloc(g.size);
	acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &g, sizeof(g));
	uint32_t *p = (uint32_t *)g.subgraphs;
	parse_ckv(getenv("CKV"));
	for (uint32_t i = 0; i < g.num_subgraphs; i++) {
		uint32_t sg = p[0]; p += 2 + p[1];
		AcdbSgIdCalKeyVector in = { 1, &sg, { 0, NULL }, { nckv, ckv } };
		AcdbBlob b = {0};
		char n[64];
		r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_NONPERSIST, &in, sizeof(in), &b, sizeof(b));
		if (!r && b.buf_size) {
			b.buf = malloc(b.buf_size);
			r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_NONPERSIST, &in, sizeof(in), &b, sizeof(b));
			sprintf(n, "cal_%08x.np", sg); dumpf(n, b.buf, b.buf_size);
		}
		printf("SG %08x nonpersist %d size %u\n", sg, r, b.buf_size);
		AcdbSgIdPersistCalData pc = {0};
		r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_PERSIST, &in, sizeof(in), &pc, sizeof(pc));
		if (!r && pc.cal_data_size) {
			pc.cal_data = malloc(pc.cal_data_size);
			r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_PERSIST, &in, sizeof(in), &pc, sizeof(pc));
			sprintf(n, "cal_%08x.p", sg); dumpf(n, pc.cal_data, pc.cal_data_size);
		}
		printf("SG %08x persist %d size %u\n", sg, r, pc.cal_data_size);
	}
}


static void amdb(int argc, char **argv)
{
	uint32_t cmds[2] = { ACDB_CMD_GET_AMDB_REGISTRATION_DATA, ACDB_CMD_GET_AMDB_BOOTUP_LOAD_MODULES };
	const char *names[2] = { "amdb_reg.bin", "amdb_load.bin" };
	for (int c = 0; c < 2; c++) {
		AcdbAmdbProcID in = { strtoul(argv[0], 0, 0) };
		AcdbBlob b = {0};
		int r = acdb_ioctl(cmds[c], &in, sizeof(in), &b, sizeof(b));
		printf("%s: size query %d, %u bytes\n", names[c], r, b.buf_size);
		if (r || !b.buf_size) continue;
		b.buf = malloc(b.buf_size);
		r = acdb_ioctl(cmds[c], &in, sizeof(in), &b, sizeof(b));
		if (!r) dumpf(names[c], b.buf, b.buf_size);
	}
}

int main(int argc, char **argv)
{
	init(argv[1]);
	if (!strcmp(argv[2], "gkvs")) gkvs(argc - 3, argv + 3);
	if (!strcmp(argv[2], "amdb")) amdb(argc - 3, argv + 3);
	if (!strcmp(argv[2], "cal")) cal(argc - 3, argv + 3);
	if (!strcmp(argv[2], "graph")) graph(argc - 3, argv + 3);
	return 0;
}
